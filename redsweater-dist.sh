#!/bin/bash
set -euo pipefail

# Configure TipTap modules to include
# Format: "package-path:export-name"
TIPTAP_MODULES=(
  "core:Editor"
  "starter-kit:StarterKit"
  "extension-text-style:TextStyle"
)

# Set absolute paths
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BUILT_PRODUCTS_DIR="${BUILT_PRODUCTS_DIR:-$SCRIPT_DIR/build}"
TIPTAP_DIR="$SCRIPT_DIR/tiptap"
VITE_TEMP_DIR="$SCRIPT_DIR/vite-tiptap-bundle"
OUTPUT_DIR="$BUILT_PRODUCTS_DIR/tiptap"

# Clone or update Tiptap repo
if [ ! -d "$TIPTAP_DIR" ]; then
  echo "Cloning Tiptap..."
  git clone https://github.com/ueberdosis/tiptap.git "$TIPTAP_DIR"
else
  echo "Updating Tiptap..."
  git -C "$TIPTAP_DIR" pull
fi

# Build Tiptap packages
echo "Building Tiptap packages..."
cd "$TIPTAP_DIR"
npx pnpm install

# Build all configured modules
BUILD_FILTERS=""
for module in "${TIPTAP_MODULES[@]}"; do
  PACKAGE_PATH="${module%%:*}"
  BUILD_FILTERS+="--filter=@tiptap/${PACKAGE_PATH} "
done
npx pnpm build $BUILD_FILTERS

# Prepare clean Vite project
echo "Creating temporary Vite bundle project..."
rm -rf "$VITE_TEMP_DIR"
mkdir "$VITE_TEMP_DIR"
cd "$VITE_TEMP_DIR"
npm init -y > /dev/null
npm install vite

# Link local Tiptap packages
mkdir -p node_modules/@tiptap
for module in "${TIPTAP_MODULES[@]}"; do
  PACKAGE_PATH="${module%%:*}"
  ln -sf "$TIPTAP_DIR/packages/${PACKAGE_PATH}" "node_modules/@tiptap/${PACKAGE_PATH}"
done

# Create bundle entry file
cat > tiptap-bundle.js <<EOF
$(for module in "${TIPTAP_MODULES[@]}"; do
  PACKAGE_PATH="${module%%:*}"
  EXPORT_NAME="${module##*:}"
  if [ "$EXPORT_NAME" = "$PACKAGE_PATH" ]; then
    echo "import ${EXPORT_NAME} from '@tiptap/${PACKAGE_PATH}'"
  else
    echo "import {${EXPORT_NAME}} from '@tiptap/${PACKAGE_PATH}'"
  fi
done)

export { $(IFS=','; echo "${TIPTAP_MODULES[*]}" | sed 's/[^:]*://g') }
EOF

# Create Vite config
cat > vite.config.js <<EOF
import { defineConfig } from 'vite'

export default defineConfig({
  build: {
    lib: {
      entry: './tiptap-bundle.js',
      name: 'TiptapBundle',
      fileName: () => 'index.js',
      formats: ['es']
    },
    outDir: "$OUTPUT_DIR",
    emptyOutDir: true,
    rollupOptions: {
      external: [], // bundle everything
    }
  }
})
EOF

# Build the bundle
echo "Bundling Tiptap..."
npx vite build

echo "✅ Done. Module available at: $OUTPUT_DIR/index.js"
