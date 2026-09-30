#!/usr/bin/env python3
"""Stage a real, verified Windows installer in the existing Ripot landing site.

No deployment is performed. Both files and links are prepared together, so the
page never claims that an absent Windows build is available.
"""
from __future__ import annotations

import argparse
import hashlib
import html
import json
import re
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path


def digest(path: Path) -> str:
    checksum = hashlib.sha256()
    with path.open('rb') as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b''):
            checksum.update(chunk)
    return checksum.hexdigest()


def once(text: str, old: str, new: str) -> str:
    if text.count(old) != 1:
        raise ValueError(f'Landing content changed; expected one occurrence of: {old[:90]}')
    return text.replace(old, new, 1)


def update_index(text: str, release: dict) -> str:
    text = re.sub(r'<!--ripot-windows-preview-start-->.*?<!--ripot-windows-preview-end-->', '', text, flags=re.S)
    text = text.replace('Android &amp; web · Windows test build', 'Available on Android, Windows &amp; web')
    # This marker allows later versions to update their URL and details in place.
    filename = release['filename']
    installer_url = f'downloads/windows/{filename}'
    checksum_url = f'{installer_url}.sha256'
    label = f"Version {release['version']} · {release['sizeBytes'] / (1024 * 1024):.1f} MB"
    button = (f'<a class="btn btn-outline" data-ripot-windows-download href="{installer_url}" download>'
              'Download for Windows</a>')
    note = (f'<p class="plan-note" data-ripot-windows-note>Windows 10/11 · Intel/AMD 64-bit PCs · '
            f'{html.escape(label)}. <a href="{checksum_url}" style="color:inherit">SHA-256 checksum</a></p>')

    if 'data-ripot-windows-download' in text:
        text, buttons = re.subn(r'<a\b[^>]*\bdata-ripot-windows-download\b[^>]*>.*?</a>', button, text, flags=re.S)
        text, notes = re.subn(r'<p\b[^>]*\bdata-ripot-windows-note\b[^>]*>.*?</p>', note, text, flags=re.S)
        if buttons != 2 or notes != 1:
            raise ValueError('Unexpected existing Windows download markup; no files changed.')
        return text

    text = once(text, 'Available on Android &amp; web', 'Available on Android, Windows &amp; web')
    text = once(text, '"operatingSystem": "Android, Web"', '"operatingSystem": "Android, Windows, Web"')
    text = once(text, 'Create, sign and share professional clinical reports on Android and the web.',
                'Create, sign and share professional clinical reports on Android, Windows and the web.')
    text = once(text, 'Get Ripot for Android or use it in your browser.',
                'Install Ripot on Android or Windows, or use it in your browser.')
    # Navigation stays compact. Add download actions only in the hero and Get Ripot panel.
    hero_start = text.index('<section class="hero-section"')
    hero_end = text.index('</section>', hero_start)
    hero = text[hero_start:hero_end]
    web_button = '<a class="btn btn-outline" href="https://ripot-web.web.app">Try Ripot Web</a>'
    hero = once(hero, web_button, button + '\n            ' + web_button)
    text = text[:hero_start] + hero + text[hero_end:]
    download_start = text.index('<section id="download"')
    download_end = text.index('</section>', download_start)
    download = text[download_start:download_end]
    download = once(download, web_button, button + web_button)
    download = once(download, '<p class="plan-note">', note + '\n            <p class="plan-note">')
    return text[:download_start] + download + text[download_end:]


def prepare(landing: Path, release_dir: Path, *, preview: bool = False) -> None:
    landing, release_dir = landing.resolve(), release_dir.resolve()
    index_path = landing / 'y/index.html'
    config_path = landing / 'firebase.json'
    aliases = json.loads((landing / '.firebaserc').read_text(encoding='utf-8-sig'))
    config = json.loads(config_path.read_text(encoding='utf-8-sig'))
    if aliases.get('projects', {}).get('default') != 'ripot-landing':
        raise ValueError('Choose the ripot-landing folder, not the Flutter app project.')
    hosting = config.get('hosting')
    if not isinstance(hosting, dict) or hosting.get('public') != 'y' or hosting.get('target'):
        raise ValueError('Expected the single-site landing configuration with public folder y.')

    release = json.loads((release_dir / 'windows-release.json').read_text(encoding='utf-8-sig'))
    if release.get('releaseStage') != 'public' and not preview:
        raise ValueError('This is an internal Windows test build. Use --preview for a local page preview; account integration and Windows validation must be resolved before a public release.')
    filename = release.get('filename', '')
    if not re.fullmatch(r'Ripot-Setup-\d+\.\d+\.\d+-\d+-windows-x64\.exe', filename):
        raise ValueError('Unexpected installer filename.')
    if release.get('product') != 'Ripot' or release.get('platform') != 'windows' or release.get('architecture') != 'x64':
        raise ValueError('Expected a Ripot Windows x64 build manifest.')
    if not re.fullmatch(r'\d+\.\d+\.\d+', str(release.get('version', ''))):
        raise ValueError('Invalid release version.')
    if filename != f"Ripot-Setup-{release['version']}-{release['build']}-windows-x64.exe":
        raise ValueError('Installer name does not match its version/build.')
    installer = release_dir / filename
    if installer.stat().st_size != release['sizeBytes'] or digest(installer) != release['sha256']:
        raise ValueError('Installer checksum or size does not match windows-release.json.')
    with installer.open('rb') as stream:
        if stream.read(2) != b'MZ':
            raise ValueError('The file is not a Windows executable.')
        stream.seek(0x3c)
        offset = int.from_bytes(stream.read(4), 'little')
        stream.seek(offset)
        if stream.read(4) != b'PE\0\0':
            raise ValueError('The file has no Windows PE header.')
    # Hash verification detects mismatched/corrupt uploads; it is not a substitute
    # for a trusted build, code signing or testing the installer on Windows.

    source = index_path.read_text(encoding='utf-8')
    updated = update_index(source, release)
    if preview:
        updated = updated.replace('Download for Windows</a>', 'Download Windows test build</a>')
        updated = updated.replace('Available on Android, Windows &amp; web', 'Android &amp; web · Windows test build')
        notice = ('<!--ripot-windows-preview-start--><aside style="padding:14px;background:#fff4d6;color:#473609;text-align:center">'
                  '<strong>Internal preview.</strong> Windows sign-in and subscription support still need production integration. '
                  'Use fictional data only. This is not a public Windows release.</aside><!--ripot-windows-preview-end-->')
        updated = once(updated, '<main id="main" tabindex="-1">', '<main id="main" tabindex="-1">' + notice)
    headers = hosting.setdefault('headers', [])
    download_rule = {
        'source': '/downloads/windows/**',
        'headers': [
            {'key': 'Cache-Control', 'value': 'public, max-age=300'},
            {'key': 'X-Content-Type-Options', 'value': 'nosniff'},
            {'key': 'Content-Disposition', 'value': 'attachment'},
        ],
    }
    headers[:] = [rule for rule in headers if rule.get('source') != download_rule['source']]
    headers.append(download_rule)
    downloads = landing / 'y/downloads/windows'
    target = downloads / filename
    if target.exists() and digest(target) != release['sha256']:
        raise ValueError('A different installer already uses this filename. Increase the app build number.')

    stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    backup = landing / '.windows-download-backups' / stamp
    backup.mkdir(parents=True)
    shutil.copy2(index_path, backup / 'index.html')
    shutil.copy2(config_path, backup / 'firebase.json')
    downloads.mkdir(parents=True, exist_ok=True)
    shutil.copy2(installer, target)
    (downloads / f'{filename}.sha256').write_text(f"{release['sha256']}  {filename}\n", encoding='ascii')
    (downloads / 'windows-release.json').write_text(json.dumps(release, indent=2) + '\n', encoding='utf-8')
    config_path.write_text(json.dumps(config, indent=2) + '\n', encoding='utf-8')
    index_path.write_text(updated, encoding='utf-8')
    print(f'Prepared {filename} and two download buttons in {index_path}')
    print(f'Original page/config saved in {backup}')
    print('Nothing has been deployed. From the landing folder, run:')
    print('  python3 verify_landing.py')
    if preview:
        print('  python3 -m http.server 8080 --directory y')
        print('Open http://localhost:8080. Do not deploy this internal preview to the public site.')
        return
    print('  firebase hosting:channel:deploy windows-preview --expires 1d --project ripot-landing')
    print('After checking the preview download: firebase deploy --only hosting --project ripot-landing')


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--landing', required=True, type=Path)
    parser.add_argument('--release-dir', required=True, type=Path)
    parser.add_argument('--preview', action='store_true', help='Prepare a clearly labelled local preview for an internal test build.')
    args = parser.parse_args()
    try:
        prepare(args.landing, args.release_dir, preview=args.preview)
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(f'No download published: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
