#!/usr/bin/env python3
"""Build and safely package Latte Reader with the installed toolchain.

Default: matched macOS 15.4 SDK direct build (no SwiftPM manifest evaluation).
--engine swiftpm retains the standard release build on healthy toolchains.
Existing artifacts are copied and checksum-verified before replacement.
"""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import platform
import plistlib
import shlex
import subprocess

ROOT = Path(__file__).resolve().parent.parent


def manifest(path):
    return {str(f.relative_to(path)): hashlib.sha256(f.read_bytes()).hexdigest()
            for f in sorted(path.rglob('*')) if f.is_file()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--engine', choices=['direct', 'swiftpm'], default='direct')
    parser.add_argument('--sdk', type=Path, default=Path('/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk'))
    parser.add_argument('--template', type=Path, help='Bundle whose identity/resources are preserved (default: existing dist app)')
    parser.add_argument('--install', action='store_true', help='Also back up and update /Applications/LatteReader.app; never stops processes')
    args = parser.parse_args()
    stamp = datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f')
    work = ROOT / '.build' / 'package' / stamp
    work.mkdir(parents=True)
    log = (work / 'delivery.log').open('w', buffering=1)

    def run(command, timeout=300):
        line = shlex.join([str(v) for v in command])
        print(line, flush=True)
        log.write(line + '\n')
        p = subprocess.run([str(v) for v in command], cwd=ROOT, stdout=subprocess.PIPE,
                           stderr=subprocess.STDOUT, text=True, timeout=timeout)
        log.write(p.stdout + '\nEXIT ' + str(p.returncode) + '\n')
        if p.returncode:
            print(p.stdout, flush=True)
            raise RuntimeError('Command failed: ' + line)
        return p.stdout

    dist = ROOT / 'dist'
    target = dist / 'LatteReader.app'
    dmg = dist / 'LatteReader.dmg'
    installed = Path('/Applications/LatteReader.app')
    template = (args.template or target).resolve()
    if not template.is_dir():
        raise RuntimeError('A template bundle with Info.plist/resources is required: ' + str(template))
    info = plistlib.loads((template / 'Contents/Info.plist').read_bytes())
    if info.get('CFBundleIdentifier') != 'com.femiofafrica.lattereader' or info.get('CFBundleExecutable') != 'LatteReader':
        raise RuntimeError('Unexpected template identity')
    if platform.system() != 'Darwin':
        raise RuntimeError('Run this build on macOS')
    if args.engine == 'direct':
        if not args.sdk.is_dir():
            raise RuntimeError('SDK unavailable; use --sdk PATH or --engine swiftpm')
        compiler = ['/usr/bin/swiftc', '-sdk', args.sdk, '-target', platform.machine() + '-apple-macosx13.0',
                    '-swift-version', '5', '-module-cache-path', work / 'ModuleCache']
        support = sorted((ROOT / 'PagePromptSupport').glob('*.swift'))
        if len(support) != 1:
            raise RuntimeError('Direct builder expects one support source; use SwiftPM for changed module layout')
        run(compiler + ['-parse-as-library', '-emit-module', '-emit-object', '-module-name', 'PagePromptSupport',
                        '-emit-module-path', work / 'PagePromptSupport.swiftmodule', *support, '-o', work / 'PagePromptSupport.o'])
        run(compiler + ['-I', work, '-parse-as-library', *sorted((ROOT / 'LatteReader').glob('*.swift')),
                        work / 'PagePromptSupport.o', '-o', work / 'LatteReader'])
        run(compiler + [*sorted((ROOT / 'PagePrompt').glob('*.swift')), '-o', work / 'PagePrompt'])
        binaries = work
    else:
        scratch = work / 'swiftpm'
        run(['/usr/bin/swift', 'build', '--build-system', 'native', '--scratch-path', scratch, '-c', 'release'])
        binaries = Path(run(['/usr/bin/swift', 'build', '--build-system', 'native', '--scratch-path', scratch,
                             '-c', 'release', '--show-bin-path']).strip())
    backup = ROOT / '.build' / 'distribution-backups' / stamp
    backup.mkdir(parents=True)
    for label, source in [('dist-app', target), ('dist-dmg', dmg), ('installed-app', installed if args.install else Path('/nonexistent'))]:
        if not source.exists():
            continue
        dest = backup / label / source.name
        dest.parent.mkdir()
        run(['/usr/bin/ditto', source, dest])
        if source.is_dir():
            assert manifest(source) == manifest(dest), 'Backup mismatch'
        else:
            assert hashlib.sha256(source.read_bytes()).digest() == hashlib.sha256(dest.read_bytes()).digest(), 'Backup mismatch'
    image_root = work / 'image-root'
    image_root.mkdir()
    staged = image_root / 'LatteReader.app'
    run(['/usr/bin/ditto', template, staged])
    for name in ['LatteReader', 'PagePrompt']:
        run(['/usr/bin/ditto', binaries / name, staged / 'Contents/MacOS' / name])
        (staged / 'Contents/MacOS' / name).chmod(0o755)
    run(['/usr/bin/codesign', '--force', '--deep', '--sign', '-', staged])
    run(['/usr/bin/codesign', '--verify', '--deep', '--strict', staged])
    expected = manifest(staged)
    (image_root / 'Applications').symlink_to('/Applications')
    image = work / 'LatteReader.dmg'
    run(['/usr/bin/hdiutil', 'create', '-volname', 'LatteReader', '-srcfolder', image_root, '-format', 'UDZO', image])
    mount = work / 'mounted-image'
    mount.mkdir()
    attached = False
    try:
        run(['/usr/bin/hdiutil', 'attach', '-readonly', '-nobrowse', '-mountpoint', mount, image])
        attached = True
        assert manifest(mount / 'LatteReader.app') == expected, 'Mounted image mismatch'
        run(['/usr/bin/codesign', '--verify', '--deep', '--strict', mount / 'LatteReader.app'])
    finally:
        if attached:
            run(['/usr/bin/hdiutil', 'detach', mount])
    dist.mkdir(exist_ok=True)
    # Move originals into the retained work directory; never delete old artifacts.
    if target.exists():
        target.rename(work / 'previous-dist.app')
    staged.rename(target)
    if dmg.exists():
        dmg.rename(work / 'previous-dist.dmg')
    image.rename(dmg)
    assert manifest(target) == expected
    if args.install:
        incoming = work / 'installed-staging.app'
        run(['/usr/bin/ditto', target, incoming])
        assert manifest(incoming) == expected
        if installed.exists():
            installed.rename(backup / 'installed-original.app')
        incoming.rename(installed)
        assert manifest(installed) == expected
        run(['/usr/bin/codesign', '--verify', '--deep', '--strict', installed])
    run(['/usr/bin/codesign', '--verify', '--deep', '--strict', target])
    result = {'app': str(target), 'dmg': str(dmg), 'backup': str(backup), 'work': str(work),
              'engine': args.engine, 'installed_updated': args.install, 'manifest': expected,
              'dmg_sha256': hashlib.sha256(dmg.read_bytes()).hexdigest()}
    (work / 'result.json').write_text(json.dumps(result, indent=2))
    print(json.dumps({k: v for k, v in result.items() if k != 'manifest'}, indent=2), flush=True)


if __name__ == '__main__':
    main()
