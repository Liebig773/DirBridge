"""Portable shell contract tests. Mount syscalls are mocked; not Android tests."""
import base64
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
LIB = (ROOT / 'module/bin/lib.sh').as_posix()
BB = os.environ.get('DIRBRIDGE_BUSYBOX')
if not BB and (ROOT / 'tools/busybox64u.exe').exists():
    BB = str(ROOT / 'tools/busybox64u.exe')

def b64(s):
    return base64.b64encode(s.encode()).decode()

def quote(s):
    return "'" + str(s).replace("'", "'\\''") + "'"

def row(alias='电报 视频', source='/storage/emulated/0/Android/data/org.telegram.messenger/files/Telegram Video', ident='m_1', enabled=1):
    return f'{ident}|{enabled}|{b64(alias)}|{b64(source)}\n'

MOCK = r'''
chown() { :; }
record() {
  local k=$(b64 "$1")
  awk -F '|' -v k="$k" '$1!=k' "$MOCK_TABLE" > "$MOCK_TABLE.tmp"
  printf '%s|%s|%s\n' "$k" "$2" "$3" >> "$MOCK_TABLE.tmp"
  mv "$MOCK_TABLE.tmp" "$MOCK_TABLE"
}
lookup() { awk -F '|' -v k="$(b64 "$1")" '$1==k {print;exit}' "$MOCK_TABLE"; }
identity() {
  local r=$(lookup "$1")
  if [ -n "$r" ]; then printf '%s\n' "${r##*|}"; else stat -Lc '%d:%i' "$1"; fi
}
is_mounted() { [ -n "$(lookup "$1")" ]; }
is_readonly() { local r=$(lookup "$1"); case "$r" in *'|ro|'*) return 0;; esac; return 1; }
mount() {
  printf '%s\n' "$*" >> "$MOCK_LOG"
  case "$1" in
    --make-private) return 0;;
    -o)
      if [ "$2" = bind ]; then
        local flag=rw
        is_readonly "$3" && flag=ro
        [ "${LOSE_RO:-0}" = 0 ] || flag=rw
        record "$4" "$flag" "$(identity "$3")"
      else
        [ "${FAIL_RO:-0}" = 0 ] || return 1
        record "$3" ro "$(identity "$3")"
      fi;;
    *) return 1;;
  esac
}
umount() {
  [ "${BUSY_TARGET:-}" != "$1" ] || return 1
  local k=$(b64 "$1")
  awk -F '|' -v k="$k" '$1!=k' "$MOCK_TABLE" > "$MOCK_TABLE.tmp"
  mv "$MOCK_TABLE.tmp" "$MOCK_TABLE"
}
'''

class Core(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='dirbridge-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.config = self.root / 'mappings.conf'
        self.config.write_text('# schema=1\n', encoding='utf-8')
        self.lower = self.root / 'media'
        self.source = self.lower / 'Android/data/org.telegram.messenger/files/Telegram Video'
        self.source.mkdir(parents=True)
        (self.source / 'video.mp4').write_bytes(b'original-video-unchanged')
        self.state = self.root / 'state'
        (self.state / 'registry').mkdir(parents=True)
        (self.state / 'stage').mkdir()
        (self.root / 'table').touch()
        (self.root / 'calls').touch()

    def shell(self, body, mock=False):
        vars = dict(LOWER=self.lower.as_posix(), EXPORT=(self.lower / 'Movies/DirBridge').as_posix(), STATE=self.state.as_posix(), MODDIR=self.root.as_posix(), CONFIG=self.config.as_posix(), NSKEY='ns123', MOCK_TABLE=(self.root / 'table').as_posix(), MOCK_LOG=(self.root / 'calls').as_posix())
        script = '. ' + quote(LIB) + '\n' + '\n'.join(k+'='+quote(v) for k,v in vars.items()) + '\n'
        if mock:
            script += MOCK
        script += body
        args = [BB, 'sh', '-c', script] if BB else ['sh', '-c', script]
        r = subprocess.run(args, capture_output=True, encoding='utf-8', errors='replace', timeout=25, env={**os.environ, 'LC_ALL':'C.UTF-8'})
        self.assertEqual(r.returncode, 0, r.stdout + '\n' + r.stderr)
        return r.stdout

    def test_shell_syntax(self):
        for file in (ROOT / 'module').rglob('*'):
            if file.suffix == '.sh' or file.name == 'dirbridge':
                cmd = [BB,'sh','-n',str(file)] if BB else ['sh','-n',str(file)]
                self.assertEqual(subprocess.run(cmd, capture_output=True).returncode, 0, str(file))

    def test_lock_immediate_success_without_timeout_option(self):
        self.shell('''flock() { [ "$#" = 2 ] && [ "$1" = -n ] && [ "$2" = 9 ]; }
sleep() { echo unexpected-sleep; return 1; }
wait_lock 9 10''')

    def test_lock_contention_retries_then_succeeds(self):
        self.shell('''printf '0' > "$STATE/attempts"
flock() {
  [ "$1" = -n ] || return 2
  n=$(cat "$STATE/attempts"); n=$((n + 1)); echo "$n" > "$STATE/attempts"
  [ "$n" -ge 3 ]
}
sleep() { echo "$1" >> "$STATE/sleeps"; }
wait_lock 9 10 || exit 1
[ "$(cat "$STATE/attempts")" = 3 ] && [ "$(wc -l < "$STATE/sleeps")" -eq 2 ]''')

    def test_lock_contention_has_bounded_wait(self):
        self.shell('''flock() { return 1; }
sleep() { echo "$1" >> "$STATE/sleeps"; }
wait_lock 9 10 2> "$STATE/error"; rc=$?
[ "$rc" = 1 ] && [ "$(wc -l < "$STATE/sleeps")" -eq 10 ] && grep -q 'Another operation' "$STATE/error"''')

    def test_lock_errors_not_reported_as_contention(self):
        self.shell('''flock() { echo 'invalid option' >&2; return 1; }
sleep() { touch "$STATE/slept"; }
wait_lock 9 10 2> "$STATE/error"; rc=$?
[ "$rc" = 2 ] && [ ! -e "$STATE/slept" ] && grep -q 'Lock acquisition failed: invalid option' "$STATE/error" && ! grep -q 'Another operation' "$STATE/error"''')

    def test_valid_config_unicode_spaces_quotes_shell_metacharacters(self):
        self.config.write_text(row(alias="电报 ' $(touch PWNED)"), encoding='utf-8')
        self.shell('validate_config "$CONFIG"')
        self.assertFalse((self.root/'PWNED').exists())

    def test_normalization(self):
        output = self.shell("valid_source '/sdcard/Android/data/a.b/files/Videos/'")
        self.assertEqual(output, '/storage/emulated/0/Android/data/a.b/files/Videos')

    def test_device_reported_telegram_path_config(self):
        path='/storage/emulated/0/Android/data/org.telegram.messenger/files/Telegram/Telegram Video/'
        self.config.write_text(row(source=path),encoding='utf-8')
        self.shell('validate_config "$CONFIG"')

    def test_human_action_status_prioritizes_errors(self):
        self.config.write_text(row(alias='Telegram'),encoding='utf-8')
        (self.state/'status.txt').write_text('S|m_1|mounted|'+b64('已挂载')+'|ns1\nS|m_1|error|'+b64('挂载失败，请重试')+'|ns2\n',encoding='utf-8')
        out=self.shell('DATA="$STATE"; human_status')
        self.assertIn('[需要处理] Telegram',out)
        self.assertIn('挂载失败，请重试',out)
        self.assertNotIn('[已挂载] Telegram',out)
        self.assertNotIn('S|m_1',out)
        self.assertNotIn(b64('挂载失败，请重试'),out)

    def test_human_action_status_respects_pause(self):
        self.config.write_text(row(alias='Telegram'),encoding='utf-8')
        (self.state/'paused').touch()
        out=self.shell('DATA="$STATE"; human_status')
        self.assertIn('[已暂停] Telegram',out)
        self.assertIn('恢复全部',out)

    def test_config_rejects_invalid_source_after_decoding(self):
        self.config.write_text(row(source='/sdcard/Download/../Android/data/app/files'),encoding='utf-8')
        self.shell('! validate_config "$CONFIG"')

    def test_invalid_sources(self):
        bad=['/data/data/a/files','/etc','/storage/emulated/10/Download/a','/storage/emulated/0/Android/data','/storage/emulated/0/Android/data/a.b','/storage/emulated/0/Movies/DirBridge','/storage/emulated/0/Movies/DirBridge/a','/sdcard/Download/../Android/data/a/b','/sdcard/Download//a','/sdcard/Download/./a','/sdcard/Download/a\nb','/sdcard/Download/a|b','/sdcard/Download/a\\b']
        for value in bad:
            with self.subTest(value=value):
                self.shell('! valid_source '+quote(value)+' >/dev/null')

    def test_invalid_aliases(self):
        for value in ['', '.', '..', '.hidden','a/b',' a','a ','a\tb','a|b','a\\b','a\nb']:
            self.shell('! valid_alias '+quote(value))

    def test_b64_rejects_corruption_and_nul(self):
        for value in ['!!','YQ','YQ===',b64('a\x00b'),b64('a\n')]:
            self.shell('! decode '+quote(value))

    def test_duplicate_ids_aliases_and_extra_fields(self):
        for value in [row()+row(alias='Other'),row()+row(ident='m_2'),row().strip()+'|extra\n',row().strip()+'|\n',row(enabled=2),row(ident='x;id')]:
            self.config.write_text(value,encoding='utf-8')
            self.shell('! validate_config "$CONFIG"')

    def test_size_and_entry_limit(self):
        self.config.write_text(''.join(row(alias=f'a{i}',ident=f'm{i}') for i in range(65)),encoding='utf-8')
        self.shell('! validate_config "$CONFIG"')

    def test_mountinfo_spaces_literal_escape(self):
        self.shell(r'''mount_info_lines() { printf '%s\n' '88 4 0:2 / /data/media/0/Movies/DirBridge/Video\040Files ro,nosuid - ext4 /dev/x rw'; }
is_mounted '/data/media/0/Movies/DirBridge/Video Files' && is_readonly '/data/media/0/Movies/DirBridge/Video Files' ''')

    def test_mount_readonly_idempotent_original_unchanged(self):
        src='/sdcard/Android/data/org.telegram.messenger/files/Telegram Video'
        out=self.shell(f'''mount_one m_1 'Telegram Video' {quote(src)}
is_readonly "$EXPORT/Telegram Video" || exit 2
count=$(wc -l < "$MOCK_LOG")
mount_one m_1 'Telegram Video' {quote(src)}
[ "$count" = "$(wc -l < "$MOCK_LOG")" ] || exit 3
''',True)
        self.assertEqual(out.count('|mounted|'),2)
        self.assertEqual((self.source/'video.mp4').read_bytes(),b'original-video-unchanged')

    def test_readonly_failure_never_publishes(self):
        out=self.shell('FAIL_RO=1; mount_one m_1 Video "/sdcard/Android/data/org.telegram.messenger/files/Telegram Video"; ! is_mounted "$EXPORT/Video"',True)
        self.assertIn('|error|',out)

    def test_publish_losing_readonly_rolls_back(self):
        out=self.shell('LOSE_RO=1; mount_one m_1 Video "/sdcard/Android/data/org.telegram.messenger/files/Telegram Video"; ! is_mounted "$EXPORT/Video"',True)
        self.assertIn('|error|',out)

    def test_existing_files_not_hidden(self):
        out=self.shell('safe_target Video; touch "$EXPORT/Video/existing.mp4"; mount_one m_1 Video "/sdcard/Android/data/org.telegram.messenger/files/Telegram Video"; ! is_mounted "$EXPORT/Video"',True)
        self.assertIn('|conflict|',out)
        self.assertTrue((self.lower/'Movies/DirBridge/Video/existing.mp4').exists())

    def test_foreign_mount_not_replaced(self):
        out=self.shell('safe_target Video; record "$EXPORT/Video" ro "900:800"; mount_one m_1 Video "/sdcard/Android/data/org.telegram.messenger/files/Telegram Video"; [ "$(identity "$EXPORT/Video")" = 900:800 ]',True)
        self.assertIn('|conflict|',out)

    def test_missing_source_is_pending(self):
        self.assertIn('|waiting|',self.shell('mount_one m_1 Video /sdcard/Download/Missing',True))

    def test_disable_unmounts_without_deleting_source(self):
        self.shell('mount_one m_1 Video "/sdcard/Android/data/org.telegram.messenger/files/Telegram Video"; cleanup_obsolete; ! is_mounted "$EXPORT/Video"',True)
        self.assertTrue((self.source/'video.mp4').exists())

    def test_busy_unmount_deferred(self):
        out=self.shell('mount_one m_1 Video "/sdcard/Android/data/org.telegram.messenger/files/Telegram Video"; BUSY_TARGET="$EXPORT/Video"; cleanup_obsolete; is_mounted "$EXPORT/Video"',True)
        self.assertIn('|busy|',out)

    def test_active_mapping_kept_on_reconcile(self):
        self.config.write_text(row(alias='Video'),encoding='utf-8')
        self.shell('mount_one m_1 Video "/sdcard/Android/data/org.telegram.messenger/files/Telegram Video"; cleanup_obsolete; is_mounted "$EXPORT/Video"',True)

    def test_pause_cleans_active_mapping(self):
        self.config.write_text(row(alias='Video'),encoding='utf-8')
        self.shell('mount_one m_1 Video "/sdcard/Android/data/org.telegram.messenger/files/Telegram Video"; touch "$STATE/paused"; cleanup_obsolete; ! is_mounted "$EXPORT/Video"',True)

if __name__ == '__main__':
    unittest.main(verbosity=2)
