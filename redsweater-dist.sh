#!/bin/bash
set -euo pipefail

# Check for dev flag (default: true for development builds)
DEV_BUILD=true
if [[ "$*" == *"--production"* ]] || [[ "$*" == *"--prod"* ]]; then
  DEV_BUILD=false
fi

# Configure TipTap modules to include
# Format: "package-path:export-name"
TIPTAP_MODULES=(
  "core:Editor"
  "starter-kit:StarterKit"
  "extension-text-style:TextStyle"
  "extension-text-align:TextAlign"
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
  # Only build tiptap packages, prosemirror packages are dependencies
  if [[ "$PACKAGE_PATH" != prosemirror-* ]]; then
    BUILD_FILTERS+="--filter=@tiptap/${PACKAGE_PATH} "
  fi
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
  # Only link tiptap packages, prosemirror packages come from npm
  if [[ "$PACKAGE_PATH" != prosemirror-* ]]; then
    ln -sf "$TIPTAP_DIR/packages/${PACKAGE_PATH}" "node_modules/@tiptap/${PACKAGE_PATH}"
  fi
done

# Link prosemirror packages from TipTap's pnpm node_modules
PROSEMIRROR_MODEL_DIR=$(find "$TIPTAP_DIR/node_modules/.pnpm" -name "prosemirror-model@*" -type d | head -1)
if [ -n "$PROSEMIRROR_MODEL_DIR" ]; then
  ln -sf "$PROSEMIRROR_MODEL_DIR/node_modules/prosemirror-model" node_modules/prosemirror-model
fi

# Create bundle entry file
cat > tiptap-bundle.js <<EOF
$(for module in "${TIPTAP_MODULES[@]}"; do
  PACKAGE_PATH="${module%%:*}"
  EXPORT_NAME="${module##*:}"
  
  # Handle different package types
  if [[ "$PACKAGE_PATH" == prosemirror-* ]]; then
    IMPORT_PATH="$PACKAGE_PATH"
  else
    IMPORT_PATH="@tiptap/$PACKAGE_PATH"
  fi
  
  if [ "$EXPORT_NAME" = "$PACKAGE_PATH" ]; then
    echo "import ${EXPORT_NAME} from '${IMPORT_PATH}'"
  else
    echo "import {${EXPORT_NAME}} from '${IMPORT_PATH}'"
  fi
done)

// Re-export prosemirror utilities from TipTap's dependencies
import {DOMSerializer} from 'prosemirror-model'

// Named exports
export { $(for module in "${TIPTAP_MODULES[@]}"; do echo -n "${module##*:}, "; done | sed 's/, $//')$([ ${#TIPTAP_MODULES[@]} -gt 0 ] && echo ", ")DOMSerializer }

// Default export containing all modules
export default {
$(for module in "${TIPTAP_MODULES[@]}"; do
  EXPORT_NAME="${module##*:}"
  echo "  ${EXPORT_NAME},"
done)
  DOMSerializer
}
EOF

# Create Vite config
cat > vite.config.js <<EOF
import { defineConfig } from 'vite'

export default defineConfig({
  build: {
    lib: {
      entry: './tiptap-bundle.js',
      name: 'TiptapBundle',
      fileName: () => 'tiptap.js',
      formats: ['es']
    },
    outDir: "$OUTPUT_DIR",
    emptyOutDir: true,
    minify: $($DEV_BUILD && echo "false" || echo "true"),
    sourcemap: $($DEV_BUILD && echo "true" || echo "false"),
    rollupOptions: {
      external: [], // bundle everything
    }
  }
})
EOF

# Build the bundle
echo "Bundling Tiptap..."
npx vite build

echo "✅ Done. Module available at: $OUTPUT_DIR/tiptap.js"
