#!/bin/bash
set -euo pipefail

BUILD_DIR="build/web"
INDEX_FILE="$BUILD_DIR/index.html"
VERSION=$(date +%Y%m%d%H%M%S)
SNIPPET_FILE="$BUILD_DIR/__version_snippet__.html"
TMP_FILE="$INDEX_FILE.tmp"

echo "Limpiando proyecto..."
flutter clean

echo "🏗️  Compilando con versión: $VERSION..."
echo "const String appBuildVersion = '$VERSION';" > lib/build_version.dart
flutter build web --release --pwa-strategy=none --dart-define=APP_VERSION=$VERSION
if [ ! -f "$INDEX_FILE" ]; then
  echo "Error: No se encontró $INDEX_FILE"
  exit 1
fi

echo "Aplicando versión en flutter_bootstrap.js..."
# Reescribe cualquier <script src="flutter_bootstrap.js..."> para meter ?v=VERSION
awk -v ver="$VERSION" '{
  gsub(/<script src="flutter_bootstrap\.js[^"]*"/,
       "<script src=\"flutter_bootstrap.js?v=" ver "\"");
  print
}' "$INDEX_FILE" > "$TMP_FILE" && mv "$TMP_FILE" "$INDEX_FILE"

echo "Aplicando versión a main.dart.js dentro de flutter_bootstrap.js..."
sed -i "s/main\.dart\.js/main.dart.js?v=$VERSION/g" "$BUILD_DIR/flutter_bootstrap.js"

echo "Eliminando bloque previo de versión (si existiera)..."
# Borra el bloque entre marcadores (multilínea) si existía
perl -0777 -pe 's/<!-- BUILD_VERSION_START -->.*?<!-- BUILD_VERSION_END -->\n?//s' \
  -i "$INDEX_FILE"

echo "Creando snippet de AUTO-UPDATE..."
cat > "$SNIPPET_FILE" <<EOF
<!-- BUILD_VERSION_START -->
<script>
(function () {
  var currentVersion = "$VERSION";
  var prev = localStorage.getItem('app_build');
  var alreadyReloaded = sessionStorage.getItem('__app_auto_reloaded__') === '1';

  function unregisterAllAndReload() {
    if ('serviceWorker' in navigator) {
      navigator.serviceWorker.getRegistrations().then(function(regs) {
        for (var i = 0; i < regs.length; i++) {
          regs[i].unregister();
        }
      }).catch(function() {});
    }
    
    if (!alreadyReloaded) {
      sessionStorage.setItem('__app_auto_reloaded__', '1');
      window.location.reload(true);
    }
  }

  if (!prev) {
    localStorage.setItem('app_build', currentVersion);
    if ('serviceWorker' in navigator) {
      navigator.serviceWorker.getRegistrations().then(function(regs) {
        for (var i = 0; i < regs.length; i++) { regs[i].unregister(); }
      });
    }
  } else if (prev !== currentVersion) {
    localStorage.setItem('app_build', currentVersion);
    unregisterAllAndReload();
  } else {
    if ('serviceWorker' in navigator) {
      navigator.serviceWorker.getRegistrations().then(function(regs) {
        for (var i = 0; i < regs.length; i++) { regs[i].unregister(); }
      });
    }
  }
})();
</script>
<!-- BUILD_VERSION_END -->
EOF

echo "Insertando snippet antes de </body>..."
# Inserta el snippet justo antes de </body>. Si no hay </body>, lo agrega al final.
awk -v file="$SNIPPET_FILE" '
BEGIN{inserted=0}
{
  if (!inserted && /<\/body>/) {
    system("cat " file);
    inserted=1;
  }
  print;
}
END{
  if (!inserted) {
    system("cat " file);
  }
}
' "$INDEX_FILE" > "$TMP_FILE" && mv "$TMP_FILE" "$INDEX_FILE"

rm -f "$SNIPPET_FILE"

echo "Versión $VERSION aplicada y auto-update habilitado en $INDEX_FILE."

echo "Configurando .htaccess para prevenir caché de index.html y archivos JS..."
cat > "$BUILD_DIR/.htaccess" <<EOF
<FilesMatch "\.(html|js)$">
    Header set Cache-Control "no-cache, no-store, must-revalidate"
    Header set Pragma "no-cache"
    Header set Expires 0
</FilesMatch>
EOF

echo "Proceso completo."