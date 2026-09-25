import unittest
from vr_audio_probe import speech_request


class Endpoint:
    def __init__(self):
        self.muted = True
        self.writes = 0

    def SetMute(self, value, _context):
        self.muted = bool(value)
        self.writes += 1

    def GetMute(self):
        return self.muted


class SpeechRequestTests(unittest.TestCase):
    def test_explicit_current_request(self):
        endpoint = Endpoint()
        self.assertTrue(speech_request(endpoint, {'id': 1, 'action': 'unmute_for_speech', 'unix_ms': 1000}, 1050)['ok'])
        self.assertEqual(endpoint.writes, 1)

    def test_cancel_stale_future_do_not_change_mute(self):
        for action, stamp in [('cancel', 1000), ('unmute_for_speech', 0), ('unmute_for_speech', 5000)]:
            endpoint = Endpoint()
            self.assertFalse(speech_request(endpoint, {'id': 2, 'action': action, 'unix_ms': stamp}, 3000)['ok'])
            self.assertEqual(endpoint.writes, 0)


if __name__ == '__main__':
    unittest.main()
