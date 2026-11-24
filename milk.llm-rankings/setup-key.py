#!/usr/bin/env python3
"""Enter API credentials locally; never echo them or pass them as arguments."""
from getpass import getpass
import os
from pathlib import Path
import tempfile


def main():
    print('Artificial Analysis — free API setup')
    print('Create a free API key at https://artificialanalysis.ai/login')
    print('The key is saved locally with owner-only permissions. Input is hidden.\n')
    key = getpass('API key: ').strip()
    if not key or any(ord(c) < 33 or ord(c) > 126 for c in key):
        print('No valid key entered; nothing changed.')
        return
    target = Path.home() / '.config/omarchy/credentials/artificial-analysis.key'
    target.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    with tempfile.NamedTemporaryFile(mode='w', dir=target.parent, delete=False) as stream:
        temporary = stream.name
        os.chmod(temporary, 0o600)
        stream.write(key + '\n')
    os.replace(temporary, target)
    print('\nKey saved. Press R in the LLM widget to load current rankings.')
    input('Press Enter to close…')


if __name__ == '__main__':
    try:
        main()
    except (KeyboardInterrupt, EOFError):
        print('\nSetup cancelled.')
