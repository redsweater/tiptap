import { Plugin, PluginKey } from 'prosemirror-state'

function isEmptyParagraph(node) {
  return node.type.name === 'paragraph' && node.content.size === 0
}

export const RedSweaterPaste = new Plugin({
  key: new PluginKey('smartPaste'),

  props: {
    handlePaste(view) {
      const { state, dispatch } = view
      const { selection, tr } = state
      const { $from } = selection

      const parent = $from.parent
      const parentPos = $from.before()

      if (isEmptyParagraph(parent)) {
        // Remove the entire empty paragraph
        const deleteTr = tr.delete(parentPos, parentPos + parent.nodeSize)
        dispatch(deleteTr)
        return false // Let default paste logic run into now-empty space
      }

      return false // Default paste
    },
  },
})
