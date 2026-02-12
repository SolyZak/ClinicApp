#!/bin/bash
set -euo pipefail

APP_NAME="DrMedhatClinic-M4"
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/${APP_NAME}.app"
LAUNCHER_SRC="$ROOT_DIR/.tmp_m4_launcher.m"

mkdir -p "$DIST_DIR"
rm -rf "$APP_BUNDLE"

mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

cat > "$APP_BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>Dr. Medhat Clinic (M4)</string>
  <key>CFBundleDisplayName</key>
  <string>Dr. Medhat Clinic (M4)</string>
  <key>CFBundleIdentifier</key>
  <string>com.drmedhat.clinic.m4</string>
  <key>CFBundleVersion</key>
  <string>1.0</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleExecutable</key>
  <string>DrMedhatClinicM4</string>
  <key>LSMinimumSystemVersion</key>
  <string>10.13</string>
</dict>
</plist>
PLIST

# Copy app resources
mkdir -p "$APP_BUNDLE/Contents/Resources/clinic"
cp -R "$ROOT_DIR/app" "$APP_BUNDLE/Contents/Resources/clinic/"
cp -R "$ROOT_DIR/static" "$APP_BUNDLE/Contents/Resources/clinic/"
cp -R "$ROOT_DIR/data" "$APP_BUNDLE/Contents/Resources/clinic/"
cp -R "$ROOT_DIR/backups" "$APP_BUNDLE/Contents/Resources/clinic/"
cp "$ROOT_DIR/requirements.txt" "$APP_BUNDLE/Contents/Resources/clinic/"
if [ -f "$ROOT_DIR/assets/app-icon.icns" ]; then
  cp "$ROOT_DIR/assets/app-icon.icns" "$APP_BUNDLE/Contents/Resources/"
  /usr/bin/plutil -replace CFBundleIconFile -string "app-icon.icns" "$APP_BUNDLE/Contents/Info.plist"
fi

# Runtime script
cat > "$APP_BUNDLE/Contents/Resources/run.sh" <<'LAUNCHER'
#!/bin/bash
set -euo pipefail

APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RES_DIR="$APP_DIR/Resources"
CLINIC_DIR="$RES_DIR/clinic"

LOG_DIR="$HOME/Library/Logs/DrMedhatClinic"
DATA_DIR="$HOME/Library/Application Support/DrMedhatClinic"
VENV_DIR="$DATA_DIR/venv"
PID_FILE="$DATA_DIR/server.pid"
LOG_FILE="$LOG_DIR/server.log"

mkdir -p "$LOG_DIR" "$DATA_DIR"

if [ -x "/opt/homebrew/bin/python3" ]; then
  PYTHON="/opt/homebrew/bin/python3"
elif [ -x "/usr/bin/python3" ]; then
  PYTHON="/usr/bin/python3"
elif command -v python3 >/dev/null 2>&1; then
  PYTHON="$(command -v python3)"
else
  /usr/bin/osascript -e 'display dialog "Python 3 is required to run Dr. Medhat Clinic.\n\nPlease install Python 3 from https://www.python.org/downloads/ and try again." buttons {"OK"} default button "OK" with icon caution'
  exit 1
fi

PYTHON_HOME="$(cd "$(dirname "$PYTHON")/.." && pwd)"
if [ -f "$VENV_DIR/pyvenv.cfg" ]; then
  if ! grep -q "$PYTHON_HOME" "$VENV_DIR/pyvenv.cfg"; then
    rm -rf "$VENV_DIR"
  fi
fi

# Create venv on first run
if [ ! -d "$VENV_DIR" ]; then
  "$PYTHON" -m venv "$VENV_DIR"
  source "$VENV_DIR/bin/activate"
  pip install --upgrade pip -q
  pip install -r "$CLINIC_DIR/requirements.txt" -q
else
  source "$VENV_DIR/bin/activate"
fi

export DRMEDHAT_DATA_DIR="$DATA_DIR"

# Stop any existing server (ensures latest app code is loaded)
if command -v pkill >/dev/null 2>&1; then
  pkill -f "uvicorn app.main:app" 2>/dev/null || true
fi

if [ -f "$PID_FILE" ]; then
  OLD_PID=$(cat "$PID_FILE")
  if ps -p "$OLD_PID" > /dev/null 2>&1; then
    kill "$OLD_PID" 2>/dev/null || true
    sleep 0.5
  fi
  rm -f "$PID_FILE"
fi

if command -v lsof >/dev/null 2>&1; then
  for pid in $(lsof -ti tcp:8000 2>/dev/null); do
    kill "$pid" 2>/dev/null || true
  done
fi


cd "$CLINIC_DIR"
"$VENV_DIR/bin/python" -m uvicorn app.main:app --app-dir "$CLINIC_DIR" --host 127.0.0.1 --port 8000 >> "$LOG_FILE" 2>&1 &
SERVER_PID=$!
echo "$SERVER_PID" > "$PID_FILE"

# Wait for server
for i in {1..30}; do
  if /usr/bin/curl -s http://localhost:8000/api/health > /dev/null 2>&1; then
    break
  fi
  sleep 0.5
done

open "http://localhost:8000/login"
cleanup() {
  if ps -p "$SERVER_PID" > /dev/null 2>&1; then
    kill "$SERVER_PID" 2>/dev/null || true
  fi
  rm -f "$PID_FILE"
}
trap cleanup EXIT
wait "$SERVER_PID"
LAUNCHER

chmod +x "$APP_BUNDLE/Contents/Resources/run.sh"

# Native arm64 launcher to reopen browser on Dock click
cat > "$LAUNCHER_SRC" <<'OBJC'
#import <Cocoa/Cocoa.h>

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property(nonatomic, strong) NSTask *task;
@end

@implementation AppDelegate
- (NSString *)runPath {
    NSString *resPath = [[NSBundle mainBundle] resourcePath];
    return [resPath stringByAppendingPathComponent:@"run.sh"];
}

- (void)startServer {
    if (self.task && self.task.isRunning) return;
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/bin/bash";
    task.arguments = @[[self runPath]];
    [task launch];
    self.task = task;
}

- (void)openBrowser {
    NSURL *url = [NSURL URLWithString:@"http://localhost:8000/login"];
    [[NSWorkspace sharedWorkspace] openURL:url];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [self startServer];
    [self openBrowser];
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag {
    [self openBrowser];
    return NO;
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    if (self.task && self.task.isRunning) {
        [self.task terminate];
    }
}
@end

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        AppDelegate *delegate = [AppDelegate new];
        [app setDelegate:delegate];
        [app run];
    }
    return 0;
}
OBJC

/usr/bin/clang -arch arm64 -mmacosx-version-min=10.13 -framework Cocoa -O2 -o "$APP_BUNDLE/Contents/MacOS/DrMedhatClinicM4" "$LAUNCHER_SRC"
rm -f "$LAUNCHER_SRC"

# Ad-hoc sign to avoid LS errors
/usr/bin/codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null 2>&1 || true

# Clean quarantine if present
/usr/bin/xattr -dr com.apple.quarantine "$APP_BUNDLE" >/dev/null 2>&1 || true

# Remove provenance to avoid LS errors on some systems
/usr/bin/xattr -dr com.apple.provenance "$APP_BUNDLE" >/dev/null 2>&1 || true


echo "Created: $APP_BUNDLE"
