// 角色代码只拥有内存中的上下文与world请求；不注册任何系统I/O或原生模块接口。
#include <Luau/Compiler.h>
#include <lua.h>
#include <lualib.h>
#include <nlohmann/json.hpp>
#include <chrono>
#include <cmath>
#include <cstdlib>
#include <iostream>
#include <memory>
#include <set>
#include <string>
#include <unordered_map>
using Json=nlohmann::json;
using Clock=std::chrono::steady_clock;
constexpr size_t MEMORY_LIMIT=32*1024*1024, LINE_LIMIT=1024*1024;
constexpr size_t TRANSPORT_CHUNK_BYTES=1024;
struct Task {
    lua_State* vm=nullptr;
    size_t bytes=0;
    std::string id;
    std::set<std::string> capabilities;
    Json pending;
    int sequence=0;
    Clock::time_point born=Clock::now(), slice;
    ~Task(){if(vm)lua_close(vm);}
};
static void* allocate(void* ud,void* ptr,size_t old_size,size_t size){
    auto& t=*static_cast<Task*>(ud);
    if(!ptr) old_size=0;
    if(!size){std::free(ptr);t.bytes-=old_size;return nullptr;}
    if(size>MEMORY_LIMIT || t.bytes-old_size>MEMORY_LIMIT-size) return nullptr;
    void* result=std::realloc(ptr,size);
    if(result)t.bytes=t.bytes-old_size+size;
    return result;
}
static void interrupt(lua_State* L,int gc){
    if(gc>=0)return;
    auto* t=static_cast<Task*>(lua_callbacks(L)->userdata);
    if(Clock::now()-t->slice>std::chrono::milliseconds(50)) luaL_error(L,"compute_budget_exceeded");
}
static void push_json(lua_State* L,const Json& value,int depth=0){
    if(depth>24)throw std::runtime_error("payload_too_deep");
    if(value.is_null())lua_pushnil(L);
    else if(value.is_boolean())lua_pushboolean(L,value.get<bool>());
    else if(value.is_number())lua_pushnumber(L,value.get<double>());
    else if(value.is_string()){auto& s=value.get_ref<const std::string&>();lua_pushlstring(L,s.data(),s.size());}
    else if(value.is_array()){
        lua_createtable(L,int(value.size()),0);int index=1;
        for(const auto& v:value){push_json(L,v,depth+1);lua_rawseti(L,-2,index++);}
    }else{
        lua_createtable(L,0,int(value.size()));
        for(auto it=value.begin();it!=value.end();++it){push_json(L,it.value(),depth+1);lua_setfield(L,-2,it.key().c_str());}
    }
}
static Json read_json(lua_State* L,int index,int depth,int& budget){
    if(depth>20 || --budget<0)throw std::runtime_error("result_size_exceeded");
    switch(lua_type(L,index)){
    case LUA_TNIL:return nullptr;
    case LUA_TBOOLEAN:return bool(lua_toboolean(L,index));
    case LUA_TNUMBER:{double n=lua_tonumber(L,index);if(!std::isfinite(n))throw std::runtime_error("non_finite_number");return n;}
    case LUA_TSTRING:{size_t n=0;const char* p=lua_tolstring(L,index,&n);if(n>65536)throw std::runtime_error("string_too_large");return std::string(p,n);}
    case LUA_TTABLE:{
        index=lua_absindex(L,index);Json result=Json::object();
        lua_pushnil(L);
        while(lua_next(L,index)){
            if(lua_type(L,-2)!=LUA_TSTRING)throw std::runtime_error("output_tables_require_string_keys");
            std::string key=lua_tostring(L,-2);
            result[key]=read_json(L,-1,depth+1,budget);lua_pop(L,1);
        }
        return result;
    }
    default:throw std::runtime_error("non_data_result");
    }
}
static int request_world(lua_State* L){
    auto* t=static_cast<Task*>(lua_callbacks(L)->userdata);
    const char* operation=luaL_checkstring(L,1);
    if(!t->capabilities.count(operation))luaL_error(L,"capability_denied");
    bool failed=false;
    {
        try{
            int budget=4096;
            Json args=read_json(L,2,0,budget);
            if(!args.is_object())throw std::runtime_error("arguments_must_be_object");
            t->pending={{"operation",operation},{"arguments",args}};
        }catch(const std::exception&){failed=true;}
    }
    if(failed)luaL_error(L,"invalid_world_request");
    return lua_yield(L,0);
}
static int resumed_request(lua_State*,int){return 1;} // 只返回本次世界回应，不把调用时的参数当结果。
static Json failure(const std::string& id,const std::string& reason){return {{"type","failed"},{"id",id},{"error",reason}};}
static Json advance(Task& task,int count){
    task.slice=Clock::now();
    int status=lua_resume(task.vm,nullptr,count);
    if(status==LUA_YIELD){
        if(task.pending.is_null())return failure(task.id,"unmanaged_yield");
        Json result={{"type","world_request"},{"id",task.id},{"sequence",++task.sequence},{"request",task.pending}};
        task.pending=nullptr;lua_settop(task.vm,0);return result;
    }
    if(status!=LUA_OK)return failure(task.id,lua_tostring(task.vm,-1)?lua_tostring(task.vm,-1):"vm_failure");
    int budget=4096;
    Json value=lua_gettop(task.vm)?read_json(task.vm,-1,0,budget):Json();
    return {{"type","completed"},{"id",task.id},{"result",value}};
}
int main(){
    std::unordered_map<std::string,std::unique_ptr<Task>> tasks;
    std::unordered_map<std::string,std::string> bytecodes;
    std::cout<<Json({{"type","ready"},{"protocol",1}}).dump()<<std::endl;
    std::string line;
    std::string assembled;
    int next_chunk=0;
    while(true){
        line.clear();bool over=false;char c;
        while(std::cin.get(c) && c!='\n'){if(line.size()<LINE_LIMIT)line+=c;else over=true;}
        if(line.empty()&&!std::cin)break;
        std::string id;
        try{
            if(over)throw std::runtime_error("message_too_large");
            auto input=Json::parse(line);
            if(input.value("op",std::string())=="transport_chunk"){
                int sequence=input.at("sequence");
                if(sequence!=next_chunk)throw std::runtime_error("invalid_transport_sequence");
                std::string hex=input.at("hex");
                if(hex.size()>TRANSPORT_CHUNK_BYTES*2 || hex.size()%2)throw std::runtime_error("invalid_transport_chunk");
                for(size_t i=0;i<hex.size();i+=2){
                    auto digit=[](char c)->int {if(c>='0'&&c<='9')return c-'0';if(c>='a'&&c<='f')return c-'a'+10;throw std::runtime_error("invalid_hex");};
                    assembled+=char(digit(hex[i])*16+digit(hex[i+1]));
                }
                if(assembled.size()>LINE_LIMIT)throw std::runtime_error("message_too_large");
                std::cout<<Json({{"type","transport_ack"},{"sequence",sequence}}).dump()<<std::endl;
                ++next_chunk;
                if(!input.value("last",false))continue;
                input=Json::parse(assembled);assembled.clear();next_chunk=0;
            }
            id=input.value("id",std::string());
            std::string op=input.at("op");
            if(op=="shutdown")break;
            if(op=="cancel"){
                bool existed=tasks.erase(id)>0;
                std::cout<<Json({{"type","cancelled"},{"id",id},{"existed",existed}}).dump()<<std::endl;continue;
            }
            if(op=="poll"){
                for(auto it=tasks.begin();it!=tasks.end();){
                    if(Clock::now()-it->second->born>std::chrono::seconds(600)){
                        std::cout<<failure(it->first,"invocation_timeout").dump()<<std::endl;it=tasks.erase(it);
                    }else ++it;
                }
                continue;
            }
            Json result;
            if(op=="start"){
                if(id.empty()||id.size()>120||tasks.count(id)||tasks.size()>=16)throw std::runtime_error("invalid_or_busy_id");
                std::string source=input.at("source");
                if(source.size()>65536)throw std::runtime_error("source_too_large");
                if(!bytecodes.count(source)){
                    if(bytecodes.size()>=32)bytecodes.clear();
                    bytecodes[source]=Luau::compile(source);
                }
                auto task=std::make_unique<Task>();task->id=id;
                for(auto& value:input.at("capabilities"))task->capabilities.insert(value.get<std::string>());
                task->vm=lua_newstate(allocate,task.get());if(!task->vm)throw std::runtime_error("allocation_failed");
                auto* L=task->vm;lua_callbacks(L)->userdata=task.get();lua_callbacks(L)->interrupt=interrupt;
                luaL_openlibs(L);
                for(auto name:{"print","require","loadstring"}){lua_pushnil(L);lua_setglobal(L,name);}
                lua_newtable(L);lua_pushcclosurek(L,request_world,"world.request",0,resumed_request);lua_setfield(L,-2,"request");lua_setglobal(L,"world");
                luaL_sandbox(L);luaL_sandboxthread(L);
                auto& code=bytecodes.at(source);
                if(luau_load(L,"skill",code.data(),code.size(),0)!=0)throw std::runtime_error(lua_tostring(L,-1));
                task->slice=Clock::now();
                if(lua_resume(L,nullptr,0)!=LUA_OK||!lua_isfunction(L,-1))throw std::runtime_error("source_must_return_function");
                push_json(L,input.value("arguments",Json::object()));push_json(L,input.value("context",Json::object()));
                tasks[id]=std::move(task);result=advance(*tasks.at(id),2);
            }else if(op=="resume"){
                if(!tasks.count(id))throw std::runtime_error("unknown_invocation");
                auto& task=*tasks.at(id);
                if(input.at("sequence").get<int>()!=task.sequence)throw std::runtime_error("stale_world_response");
                push_json(task.vm,input.at("result"));result=advance(task,1);
            }else throw std::runtime_error("unknown_protocol_operation");
            if(result.at("type")!="world_request")tasks.erase(id);
            std::cout<<result.dump()<<std::endl;
        }catch(const std::exception& e){assembled.clear();next_chunk=0;tasks.erase(id);std::cout<<failure(id,e.what()).dump()<<std::endl;}
    }
}
