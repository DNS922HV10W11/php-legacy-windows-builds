--TEST--
CVE-2026-109619: session upload progress is never recorded
--INI--
file_uploads=1
error_reporting=E_ALL&~E_NOTICE
session.save_path=
session.name=PHPSESSID
session.use_strict_mode=0
session.use_cookies=1
session.use_only_cookies=0
session.upload_progress.enabled=1
session.upload_progress.cleanup=0
session.upload_progress.prefix=upload_progress_
session.upload_progress.name=PHP_SESSION_UPLOAD_PROGRESS
session.upload_progress.freq=1%
session.upload_progress.min_freq=0.000000001
session.save_handler=files
--SKIPIF--
<?php if (!extension_loaded("session")) die("skip session extension not available"); ?>
--COOKIE--
PHPSESSID=cve2026-upload-progress
--POST_RAW--
Content-Type: multipart/form-data; boundary=---------------------------20896060251896012921717172737
-----------------------------20896060251896012921717172737
Content-Disposition: form-data; name="PHP_SESSION_UPLOAD_PROGRESS"

cve2026_session_upload_progress.php
-----------------------------20896060251896012921717172737
Content-Disposition: form-data; name="file1"; filename="file1.txt"

1
-----------------------------20896060251896012921717172737--
--FILE--
<?php
session_start();
var_dump(session_id());
var_dump(count($_FILES));
var_dump(isset($_SESSION["upload_progress_" . basename(__FILE__)]));
session_destroy();
?>
--EXPECT--
string(23) "cve2026-upload-progress"
int(1)
bool(false)
