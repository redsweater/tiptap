#!/bin/bash
set -euo pipefail

# Set absolute paths
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
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
npx pnpm build --filter=@tiptap/core --filter=@tiptap/starter-kit --filter=@tiptap/extension-text-style

# Prepare clean Vite project
echo "Creating temporary Vite bundle project..."
rm -rf "$VITE_TEMP_DIR"
mkdir "$VITE_TEMP_DIR"
cd "$VITE_TEMP_DIR"
npm init -y > /dev/null
npm install vite

# Link local Tiptap packages
mkdir -p node_modules/@tiptap
ln -sf "$TIPTAP_DIR/packages/core"        node_modules/@tiptap/core
ln -sf "$TIPTAP_DIR/packages/starter-kit" node_modules/@tiptap/starter-kit
ln -sf "$TIPTAP_DIR/packages/extension-text-style" node_modules/@tiptap/extension-text-style

# Create bundle entry file
cat > tiptap-bundle.js <<'EOF'
import {Editor} from '@tiptap/core'
import StarterKit from '@tiptap/starter-kit'
import {TextStyle} from '@tiptap/extension-text-style'

export { Editor, StarterKit, TextStyle }
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
