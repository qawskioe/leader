import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import launch_game


class LaunchTests(unittest.TestCase):
    def invoke(self, args):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder) / 'text-gateway'
            (root / 'runtime').mkdir(parents=True)
            with patch.object(launch_game, 'ROOT', root), \
                 patch.object(launch_game, 'PROJECT', Path(folder)), \
                 patch.object(launch_game, 'resolve_godot', return_value='Godot.exe'), \
                 patch.object(launch_game.subprocess, 'CREATE_NO_WINDOW', 0, create=True), \
                 patch.object(launch_game.subprocess, 'run') as run, \
                 patch.object(launch_game.subprocess, 'Popen') as start:
                launch_game.launch(args)
                return run.call_args_list, start.call_args.args[0]

    def test_no_tts_reaches_game_and_does_not_start_tts_service(self):
        services, game = self.invoke(['--no-tts', '--vr'])
        self.assertEqual(len(services), 1)
        self.assertIn('--no-tts', game[game.index('--') + 1:])
        self.assertIn('--vr', game)

    def test_automatic_play_defaults_to_text(self):
        services, game = self.invoke(['--player-control'])
        self.assertEqual(len(services), 1)
        self.assertIn('--no-tts', game[game.index('--') + 1:])

    def test_explicit_listening_starts_service_and_reaches_game(self):
        services, game = self.invoke(['--player-control', '--tts'])
        self.assertEqual(len(services), 2)
        self.assertIn('--tts', game[game.index('--') + 1:])
        self.assertNotIn('--no-tts', game)

    def test_conflicting_options_start_nothing(self):
        with patch.object(launch_game.subprocess, 'run') as run, \
             patch.object(launch_game.subprocess, 'Popen') as start:
            with self.assertRaises(ValueError):
                launch_game.launch(['--tts', '--no-tts'])
            run.assert_not_called()
            start.assert_not_called()


if __name__ == '__main__':
    unittest.main()
