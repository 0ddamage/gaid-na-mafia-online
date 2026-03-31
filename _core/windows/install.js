var APP_ID = "1906220";

var RELEASE_CERT_SHA256 = "fbf0ce154b5e4d873f5212bdef9aa3d7e61ac7ca496d1feadad47570b9a2e940";
var PATCHER_JAR_SHA256 = "d5f3555d1785790d70e7ab3642dc1c79921e4b93d02559934b5c49792f85f941";
var PATCHER_SIG_SHA256 = "c439522c8f4104294182349bec6934f92fa2d246676eece768899687a4716499";
var CLEAN_HASH_FILE_SHA256 = "60baa4cca594d0e4077ab1a149a5bac2f48b64243e7d0973e78cabfa0697f354";

var fso = new ActiveXObject("Scripting.FileSystemObject");
var shell = new ActiveXObject("WScript.Shell");
var env = shell.Environment("PROCESS");

var FX_ENABLED = false;
var shellApp = null;

function trim(s) {
  return String(s || "").replace(/^\s+|\s+$/g, "");
}

function lower(s) {
  return String(s || "").toLowerCase();
}

function stripQuotes(s) {
  s = trim(s || "");
  if (s.length >= 2) {
    var first = s.charAt(0);
    var last = s.charAt(s.length - 1);
    if ((first === '"' && last === '"') || (first === "'" && last === "'")) {
      return s.substring(1, s.length - 1);
    }
  }
  return s;
}

function normalizeSlashes(path) {
  return String(path || "").replace(/\//g, "\\");
}

function normalizeInputPath(path) {
  path = normalizeSlashes(stripQuotes(path));
  path = path.replace(/\\{2,}/g, "\\");
  if (/^[A-Za-z]:$/.test(path)) {
    path += "\\";
  }
  return path;
}

function getEnv(name) {
  try {
    return env(name) || "";
  } catch (e) {
    return "";
  }
}

function randomTag() {
  return String(new Date().getTime()) + String(Math.floor(Math.random() * 100000));
}

function joinPath() {
  var result = arguments[0];
  for (var i = 1; i < arguments.length; i++) {
    result = fso.BuildPath(result, arguments[i]);
  }
  return result;
}

function parentDir(path) {
  return fso.GetParentFolderName(path);
}

function fileExists(path) {
  return !!path && fso.FileExists(path);
}

function folderExists(path) {
  return !!path && fso.FolderExists(path);
}

function ensureFolder(path) {
  if (!path || folderExists(path)) {
    return;
  }
  var parent = parentDir(path);
  if (parent && !folderExists(parent)) {
    ensureFolder(parent);
  }
  try {
    fso.CreateFolder(path);
  } catch (e) {}
}

function deleteFile(path) {
  try {
    if (fileExists(path)) {
      fso.DeleteFile(path, true);
    }
  } catch (e) {}
}

function deleteFolder(path) {
  try {
    if (folderExists(path)) {
      fso.DeleteFolder(path, true);
    }
  } catch (e) {}
}

function quote(arg) {
  return '"' + String(arg) + '"';
}

function isPathLike(value) {
  value = String(value || "");
  return /[\\/]/.test(value) || /^[A-Za-z]:/.test(value);
}

function absolutePath(path) {
  path = normalizeInputPath(path);
  if (!path) {
    return "";
  }
  try {
    return fso.GetAbsolutePathName(path);
  } catch (e) {
    return path;
  }
}

function normalizePath(path) {
  return lower(absolutePath(path));
}

function samePath(a, b) {
  return normalizePath(a) === normalizePath(b);
}

function timestamp() {
  var d = new Date();
  function pad(n) { return n < 10 ? "0" + n : String(n); }
  return String(d.getFullYear()) + pad(d.getMonth() + 1) + pad(d.getDate()) + "-" + pad(d.getHours()) + pad(d.getMinutes()) + pad(d.getSeconds());
}

function writeTextFile(path, content) {
  ensureFolder(parentDir(path));
  var file = fso.CreateTextFile(path, true);
  file.Write(String(content));
  file.Close();
}

function appendTextFile(path, content) {
  ensureFolder(parentDir(path));
  var file = fso.OpenTextFile(path, 8, true);
  file.Write(String(content));
  file.Close();
}

function readAllText(path) {
  var file = fso.OpenTextFile(path, 1, false);
  var content = file.ReadAll();
  file.Close();
  return content;
}

function readLines(path) {
  return readAllText(path).replace(/\r/g, "").split("\n");
}

function clipForLog(text, limit) {
  return String(text || "");
}

function traceOnly(msg) {
  return;
}

function initFx() {
  if (getEnv("REPACKGENDER_NO_COLOR") === "1" || getEnv("NO_COLOR")) {
    FX_ENABLED = false;
    return;
  }
  if (getEnv("REPACKGENDER_FORCE_COLOR") === "1") {
    FX_ENABLED = true;
    return;
  }
  if (getEnv("WT_SESSION") || getEnv("ANSICON") || lower(getEnv("ConEmuANSI")) === "on") {
    FX_ENABLED = true;
    return;
  }
  var term = lower(getEnv("TERM"));
  FX_ENABLED = !!term && /(ansi|color|cygwin|msys|vt|xterm)/.test(term);
}

function colorize(code, text) {
  if (!FX_ENABLED) {
    return text;
  }
  return "\u001b[" + code + "m" + text + "\u001b[0m";
}

function prefixTag(text, color) {
  var brand = colorize("1;38;5;39", "[mod by gender]");
  var tag = colorize("1;38;5;" + color, "[" + text + "]");
  return brand + " " + tag;
}

function out(msg) {
  WScript.Echo(msg);
}

function step(label, msg) {
  out(prefixTag(label, 203) + " " + msg);
}

function info(msg) {
  out(prefixTag("INFO", 226) + " " + msg);
}

function warn(msg) {
  out(prefixTag("WARN", 214) + " " + msg);
}

function ok(msg) {
  out(prefixTag("DONE", 84) + " " + msg);
}

function fail(msg) {
  out(prefixTag("FAIL", 196) + " " + msg);
}

function initTraceLog(mode, args) {
  initFx();
}

function execCapture(commandLine) {
  traceOnly("EXEC " + commandLine);
  var execObj;
  try {
    execObj = shell.Exec(commandLine);
  } catch (e) {
    traceOnly("EXEC error: " + (e.message || e));
    return { code: 9009, stdout: "", stderr: String(e.message || e) };
  }
  while (execObj.Status === 0) {
    WScript.Sleep(50);
  }
  var stdout = "";
  var stderr = "";
  try { stdout = execObj.StdOut.ReadAll(); } catch (e1) {}
  try { stderr = execObj.StdErr.ReadAll(); } catch (e2) {}
  traceOnly("RC " + execObj.ExitCode);
  if (stdout) {
    traceOnly("STDOUT\n" + clipForLog(stdout, 6000));
  }
  if (stderr) {
    traceOnly("STDERR\n" + clipForLog(stderr, 6000));
  }
  return { code: execObj.ExitCode, stdout: stdout, stderr: stderr };
}

function execCaptureWithHeartbeat(commandLine, progressLabel, intervalSec) {
  traceOnly("EXEC " + commandLine);
  var execObj;
  try {
    execObj = shell.Exec(commandLine);
  } catch (e) {
    traceOnly("EXEC error: " + (e.message || e));
    return { code: 9009, stdout: "", stderr: String(e.message || e) };
  }
  var startMs = new Date().getTime();
  var nextReportMs = startMs + ((intervalSec || 5) * 1000);
  while (execObj.Status === 0) {
    WScript.Sleep(200);
    if (progressLabel) {
      var nowMs = new Date().getTime();
      if (nowMs >= nextReportMs) {
        info(progressLabel + "... " + Math.floor((nowMs - startMs) / 1000) + " \u0441\u0435\u043a");
        nextReportMs = nowMs + ((intervalSec || 5) * 1000);
      }
    }
  }
  var stdout = "";
  var stderr = "";
  try { stdout = execObj.StdOut.ReadAll(); } catch (e1) {}
  try { stderr = execObj.StdErr.ReadAll(); } catch (e2) {}
  traceOnly("RC " + execObj.ExitCode);
  if (stdout) {
    traceOnly("STDOUT\n" + clipForLog(stdout, 6000));
  }
  if (stderr) {
    traceOnly("STDERR\n" + clipForLog(stderr, 6000));
  }
  return { code: execObj.ExitCode, stdout: stdout, stderr: stderr };
}

function runWait(commandLine, hidden) {
  traceOnly("RUN " + commandLine);
  try {
    return shell.Run(commandLine, hidden ? 0 : 1, true);
  } catch (e) {
    traceOnly("RUN error: " + (e.message || e));
    return 9009;
  }
}

function commandExists(name) {
  return execCapture("where.exe " + name).code === 0;
}

function getSha256(path) {
  if (!fileExists(path)) {
    return "";
  }
  var result = execCapture("certutil -hashfile " + quote(path) + " SHA256");
  if (result.code !== 0) {
    return "";
  }
  var lines = (result.stdout + "\n" + result.stderr).replace(/\r/g, "").split("\n");
  for (var i = 0; i < lines.length; i++) {
    var line = trim(lines[i]).replace(/ /g, "");
    if (/^[0-9A-Fa-f]{64}$/.test(line)) {
      return lower(line);
    }
  }
  return "";
}

function verifyFileHash(path, expected, label) {
  if (!fileExists(path)) {
    throw new Error("\u0430\u0440\u0445\u0438\u0432 \u043f\u043e\u0432\u0440\u0435\u0436\u0434\u0435\u043d \u0438\u043b\u0438 \u0440\u0430\u0441\u043f\u0430\u043a\u043e\u0432\u0430\u043d \u043d\u0435 \u043f\u043e\u043b\u043d\u043e\u0441\u0442\u044c\u044e. \u0441\u043a\u0430\u0447\u0430\u0439 \u0430\u0440\u0445\u0438\u0432 \u0437\u0430\u043d\u043e\u0432\u043e");
  }
  if (!expected || /^__.*__$/.test(expected)) {
    throw new Error("\u0430\u0440\u0445\u0438\u0432 \u043f\u043e\u0432\u0440\u0435\u0436\u0434\u0435\u043d \u0438\u043b\u0438 \u0440\u0430\u0441\u043f\u0430\u043a\u043e\u0432\u0430\u043d \u043d\u0435 \u043f\u043e\u043b\u043d\u043e\u0441\u0442\u044c\u044e. \u0441\u043a\u0430\u0447\u0430\u0439 \u0430\u0440\u0445\u0438\u0432 \u0437\u0430\u043d\u043e\u0432\u043e");
  }
  var actual = getSha256(path);
  if (!actual) {
    throw new Error("\u043d\u0435 \u0441\u043c\u043e\u0433 \u043f\u0440\u043e\u0432\u0435\u0440\u0438\u0442\u044c \u0444\u0430\u0439\u043b\u044b \u0440\u0435\u043b\u0438\u0437\u0430. \u0441\u043a\u0430\u0447\u0430\u0439 \u0430\u0440\u0445\u0438\u0432 \u0437\u0430\u043d\u043e\u0432\u043e");
  }
  if (lower(actual) !== lower(expected)) {
    throw new Error("\u0430\u0440\u0445\u0438\u0432 \u043f\u043e\u0432\u0440\u0435\u0436\u0434\u0435\u043d \u0438\u043b\u0438 \u043f\u043e\u0434\u043c\u0435\u043d\u0435\u043d. \u0441\u043a\u0430\u0447\u0430\u0439 \u0430\u0440\u0445\u0438\u0432 \u0437\u0430\u043d\u043e\u0432\u043e");
  }
}

function verifyReleaseManifest() {
  if (!fileExists(RELEASE_MANIFEST)) {
    return;
  }
  var lines = readLines(RELEASE_MANIFEST);
  for (var i = 0; i < lines.length; i++) {
    var line = trim(lines[i]);
    if (!line) {
      continue;
    }
    var match = line.match(/^([0-9A-Fa-f]{64})\s+(.+)$/);
    if (!match) {
      throw new Error("\u0430\u0440\u0445\u0438\u0432 \u043f\u043e\u0432\u0440\u0435\u0436\u0434\u0435\u043d \u0438\u043b\u0438 \u0440\u0430\u0441\u043f\u0430\u043a\u043e\u0432\u0430\u043d \u043d\u0435 \u043f\u043e\u043b\u043d\u043e\u0441\u0442\u044c\u044e. \u0441\u043a\u0430\u0447\u0430\u0439 \u0430\u0440\u0445\u0438\u0432 \u0437\u0430\u043d\u043e\u0432\u043e");
    }
    var rel = match[2].replace(/\\/g, "/");
    if (/^\//.test(rel) || /^[A-Za-z]:/.test(rel) || rel.indexOf("..") !== -1) {
      throw new Error("\u0430\u0440\u0445\u0438\u0432 \u043f\u043e\u0432\u0440\u0435\u0436\u0434\u0435\u043d \u0438\u043b\u0438 \u0440\u0430\u0441\u043f\u0430\u043a\u043e\u0432\u0430\u043d \u043d\u0435 \u043f\u043e\u043b\u043d\u043e\u0441\u0442\u044c\u044e. \u0441\u043a\u0430\u0447\u0430\u0439 \u0430\u0440\u0445\u0438\u0432 \u0437\u0430\u043d\u043e\u0432\u043e");
    }
    var relParts = rel.split("/");
    var target = ROOT_DIR;
    for (var p = 0; p < relParts.length; p++) {
      target = joinPath(target, relParts[p]);
    }
    if (!fileExists(target)) {
      throw new Error("\u0430\u0440\u0445\u0438\u0432 \u043f\u043e\u0432\u0440\u0435\u0436\u0434\u0435\u043d \u0438\u043b\u0438 \u0440\u0430\u0441\u043f\u0430\u043a\u043e\u0432\u0430\u043d \u043d\u0435 \u043f\u043e\u043b\u043d\u043e\u0441\u0442\u044c\u044e. \u0441\u043a\u0430\u0447\u0430\u0439 \u0430\u0440\u0445\u0438\u0432 \u0437\u0430\u043d\u043e\u0432\u043e");
    }
    var actual = getSha256(target);
    if (lower(actual) !== lower(match[1])) {
      throw new Error("\u0430\u0440\u0445\u0438\u0432 \u043f\u043e\u0432\u0440\u0435\u0436\u0434\u0435\u043d \u0438\u043b\u0438 \u043f\u043e\u0434\u043c\u0435\u043d\u0435\u043d. \u0441\u043a\u0430\u0447\u0430\u0439 \u0430\u0440\u0445\u0438\u0432 \u0437\u0430\u043d\u043e\u0432\u043e");
    }
  }
}

function verifyReleaseBundle() {
  verifyFileHash(RELEASE_CERT, RELEASE_CERT_SHA256, "release certificate");
  verifyFileHash(PATCHER_JAR, PATCHER_JAR_SHA256, "patcher jar");
  verifyFileHash(PATCHER_SIG, PATCHER_SIG_SHA256, "patcher signature");
  verifyFileHash(CLEAN_HASH_FILE, CLEAN_HASH_FILE_SHA256, "clean.sha256");
  verifyReleaseManifest();
}

function loadSupportedHashes() {
  var lines = readLines(CLEAN_HASH_FILE);
  var list = [];
  for (var i = 0; i < lines.length; i++) {
    var line = trim(lines[i].replace(/#.*$/, ""));
    if (!line) {
      continue;
    }
    if (!/^[0-9A-Fa-f]{64}$/.test(line)) {
      throw new Error("\u043d\u0435 \u0432\u0438\u0436\u0443 \u0448\u0430\u0431\u043b\u043e\u043d \u0447\u0438\u0441\u0442\u043e\u0433\u043e \u043a\u043b\u0438\u0435\u043d\u0442\u0430 \u0432 \u0430\u0440\u0445\u0438\u0432\u0435. \u0441\u043a\u0430\u0447\u0430\u0439 \u0430\u0440\u0445\u0438\u0432 \u0437\u0430\u043d\u043e\u0432\u043e");
    }
    list.push(lower(line));
  }
  if (!list.length) {
    throw new Error("\u043d\u0435 \u0432\u0438\u0436\u0443 \u0448\u0430\u0431\u043b\u043e\u043d \u0447\u0438\u0441\u0442\u043e\u0433\u043e \u043a\u043b\u0438\u0435\u043d\u0442\u0430 \u0432 \u0430\u0440\u0445\u0438\u0432\u0435. \u0441\u043a\u0430\u0447\u0430\u0439 \u0430\u0440\u0445\u0438\u0432 \u0437\u0430\u043d\u043e\u0432\u043e");
  }
  return list;
}

function isSupportedHash(hash) {
  if (!hash) {
    return false;
  }
  hash = lower(hash);
  for (var i = 0; i < SUPPORTED_HASHES.length; i++) {
    if (SUPPORTED_HASHES[i] === hash) {
      return true;
    }
  }
  return false;
}

function isPreferredHash(hash) {
  if (!hash || !PREFERRED_CLEAN_HASH) {
    return false;
  }
  return lower(hash) === PREFERRED_CLEAN_HASH;
}

function supportedHashList() {
  return SUPPORTED_HASHES.join(", ");
}

function copyFileOverwrite(src, dst) {
  ensureFolder(parentDir(dst));
  fso.CopyFile(src, dst, true);
}

function copyWithRetries(src, dst, actionText) {
  for (var attempt = 1; attempt <= 180; attempt++) {
    try {
      copyFileOverwrite(src, dst);
      return;
    } catch (e) {
      if (attempt === 1) {
        warn("\u043d\u0435 \u043c\u043e\u0433\u0443 \u0438\u0437\u043c\u0435\u043d\u0438\u0442\u044c \u0444\u0430\u0439\u043b\u044b \u0438\u0433\u0440\u044b. \u0437\u0430\u043a\u0440\u043e\u0439 \u0438\u0433\u0440\u0443 \u0438 steam, \u043f\u043e\u0442\u043e\u043c \u043f\u0440\u043e\u0434\u043e\u043b\u0436\u0443 \u0441\u0430\u043c");
      }
      traceOnly("copy retry " + attempt + ": " + src + " -> " + dst + " :: " + (e.message || e));
      WScript.Sleep(2000);
    }
  }
  throw new Error("\u043d\u0435 \u043c\u043e\u0433\u0443 \u043e\u0431\u043d\u043e\u0432\u0438\u0442\u044c \u043a\u043b\u0438\u0435\u043d\u0442");
}

function promptLine(label) {
  try {
    WScript.StdOut.Write(label);
    return WScript.StdIn.ReadLine();
  } catch (e) {
    return "";
  }
}

function resolveGameInput(input) {
  input = normalizeInputPath(input);
  if (!input) {
    return "";
  }
  if (fileExists(input)) {
    return absolutePath(input);
  }
  if (folderExists(input)) {
    var candidates = [
      joinPath(input, "MafiaOnline.jar"),
      joinPath(input, "out-windows", "MafiaOnline.jar"),
      joinPath(input, "Mafia Online", "out-windows", "MafiaOnline.jar"),
      joinPath(input, "steamapps", "common", "Mafia Online", "out-windows", "MafiaOnline.jar")
    ];
    for (var i = 0; i < candidates.length; i++) {
      if (fileExists(candidates[i])) {
        return absolutePath(candidates[i]);
      }
    }
  }
  return "";
}

function addUnique(list, seen, value) {
  value = normalizeInputPath(value);
  if (!value) {
    return;
  }
  var key = lower(value);
  if (!seen[key]) {
    list.push(value);
    seen[key] = true;
  }
}

function regQueryValue(key, valueName) {
  var res = execCapture("reg query " + quote(key) + " /v " + quote(valueName));
  if (res.code !== 0) {
    return "";
  }
  var lines = (res.stdout || "").replace(/\r/g, "").split("\n");
  var pattern = new RegExp("^\\s*" + valueName.replace(/[-\\/\\^$*+?.()|[\]{}]/g, "\\$&") + "\\s+REG_\\w+\\s+(.+)$", "i");
  for (var i = 0; i < lines.length; i++) {
    var match = lines[i].match(pattern);
    if (match) {
      return trim(match[1]);
    }
  }
  return "";
}

function regQuerySubKeys(key) {
  var list = [];
  var res = execCapture("reg query " + quote(key));
  if (res.code !== 0) {
    return list;
  }
  var lines = (res.stdout || "").replace(/\r/g, "").split("\n");
  for (var i = 0; i < lines.length; i++) {
    var line = trim(lines[i]);
    if (!line) {
      continue;
    }
    if (line !== key && /^HKEY_/i.test(line)) {
      list.push(line);
    }
  }
  return list;
}

function parseLibraryFolders(vdfPath) {
  var libs = [];
  if (!fileExists(vdfPath)) {
    return libs;
  }
  var lines = readLines(vdfPath);
  var seen = {};
  for (var i = 0; i < lines.length; i++) {
    var match = lines[i].match(/"path"\s+"([^"]+)"/i);
    if (match) {
      var value = normalizeInputPath(match[1].replace(/\\\\/g, "\\"));
      var key = lower(value);
      if (!seen[key]) {
        libs.push(value);
        seen[key] = true;
      }
    }
  }
  return libs;
}

function parseManifestInstallDir(manifestPath) {
  if (!fileExists(manifestPath)) {
    return "";
  }
  var lines = readLines(manifestPath);
  for (var i = 0; i < lines.length; i++) {
    var match = lines[i].match(/"installdir"\s+"([^"]+)"/i);
    if (match) {
      return trim(match[1]);
    }
  }
  return "";
}

function scanForMafiaJar(base) {
  if (!folderExists(base)) {
    return "";
  }
  var res = execCapture("where.exe /R " + quote(base) + " MafiaOnline.jar");
  if (res.code !== 0) {
    return "";
  }
  var preferred = "";
  var lines = (res.stdout || "").replace(/\r/g, "").split("\n");
  for (var i = 0; i < lines.length; i++) {
    var path = normalizeInputPath(trim(lines[i]));
    if (!path || !fileExists(path)) {
      continue;
    }
    if (/\\out-windows\\MafiaOnline\.jar$/i.test(path)) {
      return absolutePath(path);
    }
    if (!preferred) {
      preferred = absolutePath(path);
    }
  }
  return preferred;
}

function collectSteamRoots() {
  var roots = [];
  var seen = {};
  var envCandidates = [
    joinPath(PROGRAM_FILES_X86, "Steam"),
    joinPath(PROGRAM_FILES, "Steam"),
    joinPath(LOCAL_APP_DATA, "Steam")
  ];
  var regQueries = [
    ["HKCU\\Software\\Valve\\Steam", "SteamPath"],
    ["HKCU\\Software\\Valve\\Steam", "SteamExe"],
    ["HKLM\\SOFTWARE\\Valve\\Steam", "InstallPath"],
    ["HKLM\\SOFTWARE\\WOW6432Node\\Valve\\Steam", "InstallPath"]
  ];
  for (var i = 0; i < envCandidates.length; i++) {
    if (folderExists(envCandidates[i])) {
      addUnique(roots, seen, envCandidates[i]);
    }
  }
  for (var j = 0; j < regQueries.length; j++) {
    var value = normalizeInputPath(regQueryValue(regQueries[j][0], regQueries[j][1]));
    if (!value) {
      continue;
    }
    if (/steam\.exe$/i.test(value) && fileExists(value)) {
      addUnique(roots, seen, parentDir(value));
    } else if (folderExists(value)) {
      addUnique(roots, seen, value);
    }
  }
  return roots;
}

function checkSteamLibrary(root) {
  if (!root || !folderExists(root)) {
    return "";
  }
  var manifest = joinPath(root, "steamapps", "appmanifest_" + APP_ID + ".acf");
  var installDir = parseManifestInstallDir(manifest) || "Mafia Online";
  var candidate = joinPath(root, "steamapps", "common", installDir, "out-windows", "MafiaOnline.jar");
  if (fileExists(candidate)) {
    return absolutePath(candidate);
  }
  if (fileExists(manifest)) {
    candidate = joinPath(root, "steamapps", "common", "Mafia Online", "out-windows", "MafiaOnline.jar");
    if (fileExists(candidate)) {
      return absolutePath(candidate);
    }
  }
  var commonDir = joinPath(root, "steamapps", "common");
  return scanForMafiaJar(commonDir);
}

function findLiveJar() {
  var roots = collectSteamRoots();
  var seen = {};
  for (var s = 0; s < roots.length; s++) {
    seen[lower(roots[s])] = true;
  }
  for (var i = 0; i < roots.length; i++) {
    var root = roots[i];
    traceOnly("steam root=" + root);
    var libs = parseLibraryFolders(joinPath(root, "steamapps", "libraryfolders.vdf"));
    for (var j = 0; j < libs.length; j++) {
      addUnique(roots, seen, libs[j]);
    }
  }
  for (var k = 0; k < roots.length; k++) {
    var live = checkSteamLibrary(roots[k]);
    if (live) {
      traceOnly("live jar found=" + live);
      return live;
    }
  }
  return "";
}

function resolveLiveJar(argLive) {
  var live = resolveGameInput(argLive);
  if (live) {
    return live;
  }
  live = findLiveJar();
  if (live) {
    return live;
  }
  out("");
  live = resolveGameInput(promptLine("\u0430\u0432\u0442\u043e\u043c\u0430\u0442\u043e\u043c \u0438\u0433\u0440\u0443 \u043d\u0435 \u043d\u0430\u0448\u0435\u043b. \u0432\u0441\u0442\u0430\u0432\u044c \u043f\u0443\u0442\u044c \u043a \u043f\u0430\u043f\u043a\u0435 \u0441 \u0438\u0433\u0440\u043e\u0439 \u0438\u043b\u0438 \u043a \u0444\u0430\u0439\u043b\u0443 \u043a\u043b\u0438\u0435\u043d\u0442\u0430: "));
  if (!live) {
    throw new Error("\u043d\u0435 \u043d\u0430\u0448\u0435\u043b \u0443\u0441\u0442\u0430\u043d\u043e\u0432\u043b\u0435\u043d\u043d\u0443\u044e \u0438\u0433\u0440\u0443");
  }
  return live;
}

function steamIsRunning() {
  var a = execCapture('tasklist /FI "IMAGENAME eq steam.exe" /NH');
  if (/steam\.exe/i.test(a.stdout)) {
    return true;
  }
  var b = execCapture('tasklist /FI "IMAGENAME eq steamwebhelper.exe" /NH');
  return /steamwebhelper\.exe/i.test(b.stdout);
}

function launchSteamIfNeeded(steamWasRunning) {
  if (getEnv("REPACKGENDER_NO_STEAM_START") === "1") {
    return;
  }
  if (steamWasRunning || steamIsRunning()) {
    return;
  }
  try {
    shell.Run('cmd /d /c start "" "steam://open/main"', 0, false);
  } catch (e) {
    traceOnly("steam open failed: " + (e.message || e));
  }
}

function requestSteamValidation() {
  if (getEnv("REPACKGENDER_NO_STEAM_VALIDATE") === "1") {
    return false;
  }
  launchSteamIfNeeded(false);
  try {
    shell.Run('cmd /d /c start "" "steam://validate/' + APP_ID + '"', 0, false);
    return true;
  } catch (e) {
    traceOnly("steam validate failed: " + (e.message || e));
    return false;
  }
}

function parseJavaMajor(output) {
  output = String(output || "");
  var match = output.match(/version\s+"([^"]+)"/i);
  if (!match) {
    match = output.match(/openjdk\s+([0-9]+)(?:[._]([0-9]+))?/i);
    if (!match) {
      return 0;
    }
    return parseInt(match[1], 10) || 0;
  }
  var version = match[1];
  var parts = version.split(/[._-]/);
  var major = parseInt(parts[0], 10);
  if (major === 1 && parts.length > 1) {
    major = parseInt(parts[1], 10);
  }
  return major || 0;
}

function probeJava(candidate) {
  candidate = normalizeInputPath(candidate);
  if (!candidate) {
    return null;
  }
  if (isPathLike(candidate) && !fileExists(candidate)) {
    return null;
  }
  var command = (isPathLike(candidate) || fileExists(candidate)) ? (quote(candidate) + " -version") : (candidate + " -version");
  var res = execCapture(command);
  if (res.code !== 0) {
    return null;
  }
  var major = parseJavaMajor((res.stdout || "") + "\n" + (res.stderr || ""));
  if (!(major > 0)) {
    return null;
  }
  return {
    candidate: candidate,
    major: major
  };
}

function chooseJava(candidate, reason) {
  var probe = probeJava(candidate);
  if (!probe) {
    return false;
  }
  traceOnly("java candidate=" + probe.candidate + " major=" + probe.major + " reason=" + reason);
  if (probe.major >= 17) {
    JAVA_BIN = probe.candidate;
    JAVA_MAJOR = probe.major;
    info("\u0434\u0436\u0430\u0432\u0430 " + probe.major + " \u0443\u0436\u0435 \u0435\u0441\u0442\u044c");
    return true;
  }
  return false;
}

function scanForJava(base) {
  if (!base || !folderExists(base)) {
    return [];
  }
  var result = execCapture("where.exe /R " + quote(base) + " java.exe");
  var list = [];
  if (result.code !== 0) {
    return list;
  }
  var lines = (result.stdout || "").replace(/\r/g, "").split("\n");
  for (var i = 0; i < lines.length; i++) {
    var path = normalizeInputPath(trim(lines[i]));
    if (path && fileExists(path)) {
      list.push(path);
    }
  }
  return list;
}

function tryGameJava(liveJar) {
  if (!liveJar) {
    return false;
  }
  var gameDir = parentDir(liveJar);
  var roots = [gameDir, parentDir(gameDir), parentDir(parentDir(gameDir))];
  var rels = [
    joinPath("bin", "java.exe"),
    joinPath("jre", "bin", "java.exe"),
    joinPath("runtime", "bin", "java.exe"),
    joinPath("runtime", "jre", "bin", "java.exe"),
    joinPath("java", "bin", "java.exe"),
    joinPath("jbr", "bin", "java.exe")
  ];
  for (var i = 0; i < roots.length; i++) {
    var base = roots[i];
    if (!base || !folderExists(base)) {
      continue;
    }
    for (var j = 0; j < rels.length; j++) {
      var candidate = joinPath(base, rels[j]);
      if (chooseJava(candidate, "game-runtime")) {
        return true;
      }
    }
  }
  for (var k = 0; k < Math.min(2, roots.length); k++) {
    var scanBase = roots[k];
    var found = scanForJava(scanBase);
    for (var n = 0; n < found.length; n++) {
      if (chooseJava(found[n], "game-scan")) {
        return true;
      }
    }
  }
  return false;
}

function tryRegistryJava() {
  var roots = [
    "HKLM\\SOFTWARE\\JavaSoft",
    "HKLM\\SOFTWARE\\WOW6432Node\\JavaSoft"
  ];
  for (var i = 0; i < roots.length; i++) {
    var families = regQuerySubKeys(roots[i]);
    for (var j = 0; j < families.length; j++) {
      var current = regQueryValue(families[j], "CurrentVersion");
      if (current) {
        var home = regQueryValue(families[j] + "\\" + current, "JavaHome");
        if (home && chooseJava(joinPath(normalizeInputPath(home), "bin", "java.exe"), "registry-current")) {
          return true;
        }
      }
      var versions = regQuerySubKeys(families[j]);
      for (var k = 0; k < versions.length; k++) {
        var versionHome = regQueryValue(versions[k], "JavaHome");
        if (versionHome && chooseJava(joinPath(normalizeInputPath(versionHome), "bin", "java.exe"), "registry-scan")) {
          return true;
        }
      }
    }
  }
  return false;
}

function tryCommonJavaFolders() {
  var roots = [
    joinPath(PROGRAM_FILES, "Java"),
    joinPath(PROGRAM_FILES_X86, "Java"),
    joinPath(PROGRAM_FILES, "Eclipse Adoptium"),
    joinPath(PROGRAM_FILES, "Zulu"),
    joinPath(PROGRAM_FILES_X86, "Zulu")
  ];
  for (var i = 0; i < roots.length; i++) {
    var list = scanForJava(roots[i]);
    for (var j = 0; j < list.length; j++) {
      if (chooseJava(list[j], "common-folder")) {
        return true;
      }
    }
  }
  return false;
}

function createShellApplication() {
  if (shellApp) {
    return shellApp;
  }
  try {
    shellApp = new ActiveXObject("Shell.Application");
  } catch (e) {
    shellApp = null;
  }
  return shellApp;
}

function downloadViaCurl(url, target, progressLabel) {
  if (!commandExists("curl.exe")) {
    return false;
  }
  return execCaptureWithHeartbeat("curl.exe -fL --retry 3 -sS -o " + quote(target) + " " + quote(url), progressLabel, 5).code === 0;
}

function downloadTextViaCurl(url, progressLabel) {
  if (!commandExists("curl.exe")) {
    return "";
  }
  var res = execCaptureWithHeartbeat("curl.exe -fL -sS --connect-timeout 8 --max-time 15 " + quote(url), progressLabel, 5);
  return res.code === 0 ? res.stdout : "";
}

function downloadViaWinHttp(url, target) {
  var request;
  try {
    request = new ActiveXObject("WinHttp.WinHttpRequest.5.1");
  } catch (e) {
    return false;
  }
  try {
    request.Open("GET", url, false);
    request.SetTimeouts(30000, 30000, 30000, 30000);
    request.Send();
    if (request.Status < 200 || request.Status >= 300) {
      return false;
    }
    var stream = new ActiveXObject("ADODB.Stream");
    stream.Type = 1;
    stream.Open();
    stream.Write(request.ResponseBody);
    stream.SaveToFile(target, 2);
    stream.Close();
    return true;
  } catch (e2) {
    return false;
  }
}

function downloadTextViaWinHttp(url) {
  var request;
  try {
    request = new ActiveXObject("WinHttp.WinHttpRequest.5.1");
  } catch (e) {
    return "";
  }
  try {
    request.Open("GET", url, false);
    request.SetTimeouts(8000, 8000, 15000, 15000);
    request.Send();
    if (request.Status < 200 || request.Status >= 300) {
      return "";
    }
    return String(request.ResponseText || "");
  } catch (e2) {
    return "";
  }
}

function downloadFile(url, target, progressLabel) {
  traceOnly("download=" + url + " -> " + target);
  deleteFile(target);
  if (downloadViaCurl(url, target, progressLabel) && fileExists(target)) {
    return true;
  }
  if (downloadViaWinHttp(url, target) && fileExists(target)) {
    return true;
  }
  if (execCaptureWithHeartbeat("certutil -urlcache -split -f " + quote(url) + " " + quote(target), progressLabel, 5).code === 0 && fileExists(target)) {
    return true;
  }
  return false;
}

function downloadText(url, progressLabel) {
  var text = downloadTextViaCurl(url, progressLabel);
  if (text) {
    return text;
  }
  return downloadTextViaWinHttp(url);
}

function extractZip(archive, dst) {
  if (commandExists("tar.exe")) {
    var tarRes = execCaptureWithHeartbeat("tar.exe -xf " + quote(archive) + " -C " + quote(dst), "\u0440\u0430\u0441\u043f\u0430\u043a\u043e\u0432\u044b\u0432\u0430\u044e \u0434\u0436\u0430\u0432\u0443", 5);
    if (tarRes.code === 0 && findFirstFile(dst, "java.exe")) {
      return true;
    }
    traceOnly("tar.exe extraction did not produce java.exe");
  }
  var app = createShellApplication();
  if (!app) {
    return false;
  }
  ensureFolder(dst);
  var srcNs = app.NameSpace(archive);
  var dstNs = app.NameSpace(dst);
  if (!srcNs || !dstNs) {
    return false;
  }
  try {
    dstNs.CopyHere(srcNs.Items(), 16 + 4 + 1024);
  } catch (e) {
    traceOnly("zip extract failed: " + (e.message || e));
    return false;
  }
  var startMs = new Date().getTime();
  var nextReportMs = startMs + 5000;
  for (var i = 0; i < 240; i++) {
    if (findFirstFile(dst, "java.exe")) {
      WScript.Sleep(1500);
      return true;
    }
    WScript.Sleep(500);
    var nowMs = new Date().getTime();
    if (nowMs >= nextReportMs) {
      info("\u0440\u0430\u0441\u043f\u0430\u043a\u043e\u0432\u044b\u0432\u0430\u044e \u0434\u0436\u0430\u0432\u0443... " + Math.floor((nowMs - startMs) / 1000) + " \u0441\u0435\u043a");
      nextReportMs = nowMs + 5000;
    }
  }
  return false;
}

function findFirstFile(folderPath, targetName) {
  if (!folderExists(folderPath)) {
    return "";
  }
  var files = new Enumerator(fso.GetFolder(folderPath).Files);
  for (; !files.atEnd(); files.moveNext()) {
    var file = files.item();
    if (lower(file.Name) === lower(targetName)) {
      return file.Path;
    }
  }
  var folders = new Enumerator(fso.GetFolder(folderPath).SubFolders);
  for (; !folders.atEnd(); folders.moveNext()) {
    var found = findFirstFile(folders.item().Path, targetName);
    if (found) {
      return found;
    }
  }
  return "";
}

function copyFolderRecursive(src, dst) {
  ensureFolder(dst);
  var srcFolder = fso.GetFolder(src);
  var files = new Enumerator(srcFolder.Files);
  for (; !files.atEnd(); files.moveNext()) {
    var file = files.item();
    copyFileOverwrite(file.Path, joinPath(dst, file.Name));
  }
  var subFolders = new Enumerator(srcFolder.SubFolders);
  for (; !subFolders.atEnd(); subFolders.moveNext()) {
    var folder = subFolders.item();
    copyFolderRecursive(folder.Path, joinPath(dst, folder.Name));
  }
}

function installLocalJava() {
  var localJava = joinPath(JAVA_RUNTIME_DIR, "bin", "java.exe");
  if (chooseJava(localJava, "existing-local-runtime")) {
    return true;
  }

  var arch = lower(getEnv("PROCESSOR_ARCHITEW6432") || getEnv("PROCESSOR_ARCHITECTURE") || "amd64");
  var javaArch = arch === "arm64" ? "aarch64" : "x64";
  var apiUrl = "https://api.adoptium.net/v3/binary/latest/17/ga/windows/" + javaArch + "/jre/hotspot/normal/eclipse?project=jdk";
  var tmpDir = joinPath(TEMP_DIR, "repackgender-java-" + randomTag());
  var archive = joinPath(tmpDir, "java.zip");
  var extractDir = joinPath(tmpDir, "extract");
  ensureFolder(tmpDir);
  ensureFolder(extractDir);

  info("\u0434\u0436\u0430\u0432\u0443 \u043d\u0435 \u043d\u0430\u0448\u0435\u043b. \u0441\u043a\u0430\u0447\u0438\u0432\u0430\u044e \u0441\u0432\u043e\u044e \u043a\u043e\u043f\u0438\u044e");
  info("\u0441\u043a\u0430\u0447\u0438\u0432\u0430\u044e \u0434\u0436\u0430\u0432\u0443");
  if (!downloadFile(apiUrl, archive, "\u0441\u043a\u0430\u0447\u0438\u0432\u0430\u044e \u0434\u0436\u0430\u0432\u0443")) {
    deleteFolder(tmpDir);
    return false;
  }
  info("\u0434\u0436\u0430\u0432\u0443 \u0441\u043a\u0430\u0447\u0430\u043b");

  info("\u0440\u0430\u0441\u043f\u0430\u043a\u043e\u0432\u044b\u0432\u0430\u044e \u0434\u0436\u0430\u0432\u0443");
  if (!extractZip(archive, extractDir)) {
    deleteFolder(tmpDir);
    return false;
  }
  info("\u0434\u0436\u0430\u0432\u0443 \u0440\u0430\u0441\u043f\u0430\u043a\u043e\u0432\u0430\u043b");

  var javaExe = findFirstFile(extractDir, "java.exe");
  if (!javaExe) {
    deleteFolder(tmpDir);
    return false;
  }
  var javaHome = parentDir(parentDir(javaExe));
  if (!fileExists(joinPath(javaHome, "bin", "java.exe"))) {
    deleteFolder(tmpDir);
    return false;
  }

  deleteFolder(JAVA_RUNTIME_DIR);
  ensureFolder(parentDir(JAVA_RUNTIME_DIR));
  info("\u043a\u043e\u043f\u0438\u0440\u0443\u044e \u0434\u0436\u0430\u0432\u0443 \u0432 \u043b\u043e\u043a\u0430\u043b\u044c\u043d\u0443\u044e \u043f\u0430\u043f\u043a\u0443");
  copyFolderRecursive(javaHome, JAVA_RUNTIME_DIR);
  info("\u0434\u0436\u0430\u0432\u0430 \u0433\u043e\u0442\u043e\u0432\u0430");
  deleteFolder(tmpDir);
  return chooseJava(joinPath(JAVA_RUNTIME_DIR, "bin", "java.exe"), "fresh-local-runtime");
}

function ensureJava(liveJar) {
  var envJava = normalizeInputPath(getEnv("REPACKGENDER_JAVA_BIN"));
  if (envJava && chooseJava(envJava, "env-override")) {
    return;
  }
  if (chooseJava(joinPath(JAVA_RUNTIME_DIR, "bin", "java.exe"), "cached-local-runtime")) {
    return;
  }
  if (tryGameJava(liveJar)) {
    return;
  }
  var javaHome = normalizeInputPath(getEnv("JAVA_HOME"));
  if (javaHome && chooseJava(joinPath(javaHome, "bin", "java.exe"), "java-home")) {
    return;
  }
  if (tryRegistryJava()) {
    return;
  }
  if (chooseJava("java.exe", "path-java")) {
    return;
  }
  if (tryCommonJavaFolders()) {
    return;
  }
  if (!installLocalJava()) {
    throw new Error("\u043d\u0435 \u0441\u043c\u043e\u0433 \u043f\u043e\u0434\u0433\u043e\u0442\u043e\u0432\u0438\u0442\u044c \u0434\u0436\u0430\u0432\u0443. \u043f\u0440\u043e\u0432\u0435\u0440\u044c \u0438\u043d\u0442\u0435\u0440\u043d\u0435\u0442 \u0438 \u0437\u0430\u043f\u0443\u0441\u0442\u0438 \u0435\u0449\u0435 \u0440\u0430\u0437");
  }
}

function getBackupsSorted() {
  var list = [];
  if (!folderExists(BACKUP_DIR)) {
    return list;
  }
  var files = new Enumerator(fso.GetFolder(BACKUP_DIR).Files);
  for (; !files.atEnd(); files.moveNext()) {
    var file = files.item();
    if (/\.jar$/i.test(file.Name)) {
      list.push({ path: file.Path, time: new Date(file.DateLastModified).getTime() });
    }
  }
  list.sort(function (a, b) { return b.time - a.time; });
  return list;
}

function waitForPreferredLiveClean(liveJar, timeoutSec) {
  timeoutSec = parseInt(timeoutSec, 10);
  if (!(timeoutSec > 0)) {
    timeoutSec = 900;
  }
  info("\u0436\u0434\u0443 \u043f\u043e\u043a\u0430 steam \u0437\u0430\u043a\u043e\u043d\u0447\u0438\u0442 \u043f\u0440\u043e\u0432\u0435\u0440\u043a\u0443 \u0444\u0430\u0439\u043b\u043e\u0432. \u043c\u0430\u043a\u0441\u0438\u043c\u0443\u043c " + timeoutSec + " \u0441\u0435\u043a");
  for (var elapsed = 0; elapsed < timeoutSec; elapsed += 5) {
    var liveSha = getSha256(liveJar);
    if (isPreferredHash(liveSha)) {
      info("steam \u0437\u0430\u043a\u043e\u043d\u0447\u0438\u043b \u043f\u0440\u043e\u0432\u0435\u0440\u043a\u0443. \u0447\u0438\u0441\u0442\u044b\u0439 \u043a\u043b\u0438\u0435\u043d\u0442 \u043d\u0430\u0448\u0435\u043b");
      return true;
    }
    WScript.Sleep(5000);
  }
  info("steam \u0432\u043e\u0432\u0440\u0435\u043c\u044f \u0447\u0438\u0441\u0442\u044b\u0439 \u043a\u043b\u0438\u0435\u043d\u0442 \u043d\u0435 \u043e\u0442\u0434\u0430\u043b");
  return false;
}

function prepareClean(liveJar, suppliedClean) {
  ensureFolder(parentDir(CLEAN_JAR));
  ensureFolder(parentDir(PATCHED_JAR));
  ensureFolder(BACKUP_DIR);

  if (fileExists(CLEAN_JAR)) {
    if (isPreferredHash(getSha256(CLEAN_JAR))) {
      info("\u0431\u0435\u0440\u0443 \u043b\u043e\u043a\u0430\u043b\u044c\u043d\u044b\u0439 \u0447\u0438\u0441\u0442\u044b\u0439 \u043a\u043b\u0438\u0435\u043d\u0442");
      return;
    }
    info("\u043b\u043e\u043a\u0430\u043b\u044c\u043d\u044b\u0439 \u0447\u0438\u0441\u0442\u044b\u0439 \u043a\u043b\u0438\u0435\u043d\u0442 \u0443\u0441\u0442\u0430\u0440\u0435\u043b. \u0441\u043e\u0431\u0438\u0440\u0430\u044e \u0437\u0430\u043d\u043e\u0432\u043e");
    deleteFile(CLEAN_JAR);
  }

  var resolvedClean = resolveGameInput(suppliedClean);
  if (resolvedClean && isPreferredHash(getSha256(resolvedClean))) {
    info("\u0431\u0435\u0440\u0443 \u0443\u043a\u0430\u0437\u0430\u043d\u043d\u044b\u0439 \u0447\u0438\u0441\u0442\u044b\u0439 \u043a\u043b\u0438\u0435\u043d\u0442");
    copyFileOverwrite(resolvedClean, CLEAN_JAR);
    return;
  }
  if (resolvedClean) {
    info("\u0443 \u0443\u043a\u0430\u0437\u0430\u043d\u043d\u043e\u0433\u043e \u043a\u043b\u0438\u0435\u043d\u0442\u0430 \u043d\u0435 \u0442\u0430 \u0432\u0435\u0440\u0441\u0438\u044f");
  }

  var liveSha = getSha256(liveJar);
  if (isPreferredHash(liveSha)) {
    info("\u0442\u0435\u043a\u0443\u0449\u0438\u0439 \u043a\u043b\u0438\u0435\u043d\u0442 \u0443\u0436\u0435 \u0447\u0438\u0441\u0442\u044b\u0439. \u0431\u0435\u0440\u0443 \u0435\u0433\u043e");
    copyFileOverwrite(liveJar, CLEAN_JAR);
    return;
  }

  var backups = getBackupsSorted();
  for (var i = 0; i < backups.length; i++) {
    if (isPreferredHash(getSha256(backups[i].path))) {
      info("\u043d\u0430\u0448\u0435\u043b \u0447\u0438\u0441\u0442\u044b\u0439 \u043a\u043b\u0438\u0435\u043d\u0442 \u0432 \u0440\u0435\u0437\u0435\u0440\u0432\u043d\u043e\u0439 \u043a\u043e\u043f\u0438\u0438");
      copyFileOverwrite(backups[i].path, CLEAN_JAR);
      return;
    }
  }

  info("\u0447\u0438\u0441\u0442\u044b\u0439 \u043a\u043b\u0438\u0435\u043d\u0442 \u043b\u043e\u043a\u0430\u043b\u044c\u043d\u043e \u043d\u0435 \u043d\u0430\u0448\u0435\u043b. \u0437\u0430\u043f\u0443\u0441\u043a\u0430\u044e \u043f\u0440\u043e\u0432\u0435\u0440\u043a\u0443 \u0444\u0430\u0439\u043b\u043e\u0432 \u0432 steam");
  if (requestSteamValidation()) {
    var timeoutSec = getEnv("REPACKGENDER_STEAM_VALIDATE_TIMEOUT") || "900";
    if (waitForPreferredLiveClean(liveJar, timeoutSec)) {
      copyFileOverwrite(liveJar, CLEAN_JAR);
      return;
    }
  }

  if (getEnv("REPACKGENDER_ALLOW_UNSUPPORTED_CLEAN")) {
    warn("\u0447\u0438\u0441\u0442\u044b\u0439 \u043a\u043b\u0438\u0435\u043d\u0442 \u043f\u043e\u0434\u0442\u0432\u0435\u0440\u0434\u0438\u0442\u044c \u043d\u0435 \u0441\u043c\u043e\u0433. \u0431\u0435\u0440\u0443 \u0442\u0435\u043a\u0443\u0449\u0438\u0439 \u043a\u043b\u0438\u0435\u043d\u0442 \u043a\u0430\u043a \u043e\u0441\u043d\u043e\u0432\u0443");
    copyFileOverwrite(liveJar, CLEAN_JAR);
    return;
  }

  throw new Error("\u043d\u0435 \u0441\u043c\u043e\u0433 \u043f\u043e\u0434\u0433\u043e\u0442\u043e\u0432\u0438\u0442\u044c \u0447\u0438\u0441\u0442\u044b\u0439 \u043a\u043b\u0438\u0435\u043d\u0442. \u0437\u0430\u043f\u0443\u0441\u0442\u0438 \u043f\u0440\u043e\u0432\u0435\u0440\u043a\u0443 \u0444\u0430\u0439\u043b\u043e\u0432 \u0432 steam \u0438 \u043f\u043e\u043f\u0440\u043e\u0431\u0443\u0439 \u0435\u0449\u0435 \u0440\u0430\u0437");
}

function buildJavaCommand(args) {
  var prefix = isPathLike(JAVA_BIN) ? quote(JAVA_BIN) : JAVA_BIN;
  return prefix + " " + args.join(" ");
}

function runPatcher(cleanJar, outJar) {
  var res = execCapture(buildJavaCommand(["-jar", quote(PATCHER_JAR), quote(cleanJar), quote(outJar)]));
  return res.code;
}

function retryPatcherWithLocalJava(cleanJar, outJar) {
  var localJava = joinPath(JAVA_RUNTIME_DIR, "bin", "java.exe");
  if (samePath(JAVA_BIN, localJava)) {
    return 1;
  }
  info("\u0442\u0435\u043a\u0443\u0449\u0430\u044f \u0434\u0436\u0430\u0432\u0430 \u043d\u0435 \u043f\u043e\u0434\u043e\u0448\u043b\u0430. \u0441\u043a\u0430\u0447\u0438\u0432\u0430\u044e \u0441\u0432\u043e\u044e \u0434\u0436\u0430\u0432\u0443 \u0438 \u043f\u0440\u043e\u0431\u0443\u044e \u0435\u0449\u0435 \u0440\u0430\u0437");
  if (!installLocalJava() || !samePath(JAVA_BIN, localJava)) {
    return 1;
  }
  return runPatcher(cleanJar, outJar);
}

function installPatch(argLive, argClean) {
  step("1/7", "\u0438\u0449\u0443 \u0438\u0433\u0440\u0443");
  var liveJar = resolveLiveJar(argLive);
  var steamWasRunning = steamIsRunning();

  info("\u0438\u0433\u0440\u0443 \u043d\u0430\u0448\u0435\u043b");

  step("2/7", "\u043f\u0440\u043e\u0432\u0435\u0440\u044f\u044e \u0430\u0440\u0445\u0438\u0432");
  verifyReleaseBundle();

  step("3/7", "\u0438\u0449\u0443 \u0434\u0436\u0430\u0432\u0443");
  ensureJava(liveJar);

  step("4/7", "\u0438\u0449\u0443 \u0447\u0438\u0441\u0442\u044b\u0439 \u043a\u043b\u0438\u0435\u043d\u0442");
  prepareClean(liveJar, argClean);

  ensureFolder(BACKUP_DIR);
  ensureFolder(parentDir(PATCHED_JAR));

  var ts = timestamp();
  step("5/7", "\u043f\u0430\u0442\u0447\u0443 \u043a\u043b\u0438\u0435\u043d\u0442");
  var patchRc = runPatcher(CLEAN_JAR, PATCHED_JAR);
  if (patchRc !== 0) {
    patchRc = retryPatcherWithLocalJava(CLEAN_JAR, PATCHED_JAR);
  }
  if (patchRc !== 0) {
    throw new Error("\u043d\u0435 \u0441\u043c\u043e\u0433 \u043f\u0440\u043e\u043f\u0430\u0442\u0447\u0438\u0442\u044c \u043a\u043b\u0438\u0435\u043d\u0442. \u0437\u0430\u043f\u0443\u0441\u0442\u0438 \u0435\u0449\u0435 \u0440\u0430\u0437");
  }

  step("6/7", "\u0434\u0435\u043b\u0430\u044e \u0440\u0435\u0437\u0435\u0440\u0432\u043d\u0443\u044e \u043a\u043e\u043f\u0438\u044e");
  var backupTarget = joinPath(BACKUP_DIR, "live-before-install-" + ts + ".jar");
  copyWithRetries(liveJar, backupTarget, "create a live-file backup");

  step("7/7", "\u043f\u043e\u0434\u043c\u0435\u043d\u044f\u044e \u043a\u043b\u0438\u0435\u043d\u0442");
  copyWithRetries(PATCHED_JAR, liveJar, "replace the game file");
  deleteFile(PATCHED_JAR);

  out("");
  ok("\u043f\u0430\u0442\u0447 \u043f\u043e\u0441\u0442\u0430\u0432\u0438\u043b");

  if (!steamWasRunning) {
    launchSteamIfNeeded(false);
    info("steam \u0431\u044b\u043b \u0437\u0430\u043a\u0440\u044b\u0442. \u043f\u0440\u043e\u0431\u0443\u044e \u043e\u0442\u043a\u0440\u044b\u0442\u044c \u0435\u0433\u043e");
  }
}

function restoreClean(argLive) {
  step("1/3", "\u0438\u0449\u0443 \u0438\u0433\u0440\u0443");
  var liveJar = resolveLiveJar(argLive);
  if (!fileExists(CLEAN_JAR)) {
    throw new Error("\u043d\u0435 \u043d\u0430\u0448\u0435\u043b \u043b\u043e\u043a\u0430\u043b\u044c\u043d\u044b\u0439 \u0447\u0438\u0441\u0442\u044b\u0439 \u043a\u043b\u0438\u0435\u043d\u0442. \u0432\u043e\u0437\u0432\u0440\u0430\u0449\u0430\u0442\u044c \u043d\u0435\u0447\u0435\u0433\u043e");
  }
  var restoreSource = CLEAN_JAR;
  var cleanSha = getSha256(restoreSource);
  if (!isPreferredHash(cleanSha)) {
    var backups = getBackupsSorted();
    restoreSource = "";
    for (var i = 0; i < backups.length; i++) {
      var backupSha = getSha256(backups[i].path);
      if (isPreferredHash(backupSha)) {
        restoreSource = backups[i].path;
        cleanSha = backupSha;
        info("\u043b\u043e\u043a\u0430\u043b\u044c\u043d\u044b\u0439 clean \u0443\u0441\u0442\u0430\u0440\u0435\u043b. \u0431\u0435\u0440\u0443 \u0430\u043a\u0442\u0443\u0430\u043b\u044c\u043d\u044b\u0439 clean \u0438\u0437 backup");
        break;
      }
    }
    if (!restoreSource) {
      throw new Error("\u043b\u043e\u043a\u0430\u043b\u044c\u043d\u044b\u0439 clean \u0443\u0441\u0442\u0430\u0440\u0435\u043b. \u0437\u0430\u043f\u0443\u0441\u0442\u0438 \u0432 steam \u00ab\u043f\u0440\u043e\u0432\u0435\u0440\u0438\u0442\u044c \u0446\u0435\u043b\u043e\u0441\u0442\u043d\u043e\u0441\u0442\u044c \u0444\u0430\u0439\u043b\u043e\u0432\u00bb, \u0437\u0430\u0442\u0435\u043c \u0441\u043d\u043e\u0432\u0430 \u0443\u0441\u0442\u0430\u043d\u043e\u0432\u043a\u0443 \u043c\u043e\u0434\u0430");
    }
  }
  ensureFolder(BACKUP_DIR);
  var ts = timestamp();
  var backupTarget = joinPath(BACKUP_DIR, "live-before-restore-" + ts + ".jar");

  step("2/3", "\u0434\u0435\u043b\u0430\u044e \u0440\u0435\u0437\u0435\u0440\u0432\u043d\u0443\u044e \u043a\u043e\u043f\u0438\u044e");
  copyWithRetries(liveJar, backupTarget, "create a live-file backup");

  step("3/3", "\u0432\u043e\u0437\u0432\u0440\u0430\u0449\u0430\u044e \u0447\u0438\u0441\u0442\u044b\u0439 \u043a\u043b\u0438\u0435\u043d\u0442");
  copyWithRetries(restoreSource, liveJar, "restore the clean jar");

  out("");
  ok("\u0447\u0438\u0441\u0442\u044b\u0439 \u043a\u043b\u0438\u0435\u043d\u0442 \u0432\u0435\u0440\u043d\u0443\u043b");
}

var scriptDir = parentDir(WScript.ScriptFullName);
var CORE_DIR = parentDir(scriptDir);
var ROOT_DIR = parentDir(CORE_DIR);
var LOCAL_APP_DATA = getEnv("LOCALAPPDATA") || (getEnv("USERPROFILE") ? joinPath(getEnv("USERPROFILE"), "AppData", "Local") : getEnv("TEMP"));
var PROGRAM_FILES = getEnv("ProgramFiles") || "C:\\Program Files";
var PROGRAM_FILES_X86 = getEnv("ProgramFiles(x86)") || PROGRAM_FILES;
var TEMP_DIR = getEnv("TEMP") || LOCAL_APP_DATA;

var PATCHER_JAR = joinPath(CORE_DIR, "bin", "repackgender-core.jar");
var PATCHER_SIG = joinPath(CORE_DIR, "bin", "repackgender-core.jar.sig");
var RELEASE_CERT = joinPath(CORE_DIR, "keys", "release-signing.cer");
var RELEASE_MANIFEST = joinPath(CORE_DIR, "release-manifest.txt");
var CLEAN_HASH_FILE = joinPath(CORE_DIR, "clean.sha256");
var STATE_DIR = joinPath(LOCAL_APP_DATA, "repackgender");
var CLEAN_JAR = joinPath(STATE_DIR, "clean", "client-clean.jar");
var PATCHED_JAR = joinPath(STATE_DIR, "build", "client-patched.jar");
var BACKUP_DIR = joinPath(STATE_DIR, "backups");
var JAVA_RUNTIME_DIR = joinPath(STATE_DIR, "runtime", "java");
var JAVA_BIN = "";
var JAVA_MAJOR = 0;

var args = [];
for (var ai = 0; ai < WScript.Arguments.length; ai++) {
  args.push(String(WScript.Arguments.Item(ai)));
}
var mode = "install";
if (args.length && lower(args[0]) === "restore") {
  mode = "restore";
  args.shift();
} else if (args.length && lower(args[0]) === "install") {
  args.shift();
}
var argLive = args.length > 0 ? args[0] : "";
var argClean = args.length > 1 ? args[1] : "";
var SUPPORTED_HASHES;
var PREFERRED_CLEAN_HASH = "";

try {
  initTraceLog(mode, args);
  if (!fileExists(CLEAN_HASH_FILE)) {
    throw new Error("\u043d\u0435 \u0432\u0438\u0436\u0443 \u0444\u0430\u0439\u043b\u044b \u0440\u0435\u043b\u0438\u0437\u0430. \u0441\u043a\u0430\u0447\u0430\u0439 \u0430\u0440\u0445\u0438\u0432 \u0437\u0430\u043d\u043e\u0432\u043e");
  }
  SUPPORTED_HASHES = loadSupportedHashes();
  PREFERRED_CLEAN_HASH = SUPPORTED_HASHES.length ? SUPPORTED_HASHES[0] : "";
  if (mode === "install") {
    if (!fileExists(PATCHER_JAR) || !fileExists(PATCHER_SIG) || !fileExists(RELEASE_CERT)) {
      throw new Error("\u043d\u0435 \u0432\u0438\u0436\u0443 \u0444\u0430\u0439\u043b\u044b \u0440\u0435\u043b\u0438\u0437\u0430. \u0441\u043a\u0430\u0447\u0430\u0439 \u0430\u0440\u0445\u0438\u0432 \u0437\u0430\u043d\u043e\u0432\u043e");
    }
    installPatch(argLive, argClean);
  } else if (mode === "restore") {
    restoreClean(argLive);
  } else {
    throw new Error("\u043d\u0435 \u043f\u043e\u043d\u0438\u043c\u0430\u044e \u0440\u0435\u0436\u0438\u043c \u0437\u0430\u043f\u0443\u0441\u043a\u0430");
  }
  WScript.Quit(0);
} catch (e) {
  out("");
  fail(e && e.message ? e.message : e);
  WScript.Quit(1);
}
