import React, {PropTypes} from 'react'

import {
 Editor,
 ContentState,
 convertFromHTML,
 EditorState,
 RichUtils
} from 'draft-js'

import InlineStyleControls from './InlineStyleControls'
import {stateToHTML} from 'draft-js-export-html'

class Draft extends React.Component {
  constructor(props) {
    super(props)

    const blocksFromHTML = convertFromHTML(props.initialValue)
    const state = ContentState.createFromBlockArray(
      blocksFromHTML.contentBlocks,
      blocksFromHTML.entityMap
    )
    this.state = {editorState: EditorState.createWithContent(state)}

    this.focus = () => this.refs.editor.focus()
    this.onChange = (editorState) => {
      this.setState({editorState})
    }

    this.onBlur = (editorState) => {
      props.onBlur(stateToHTML(this.state.editorState.getCurrentContent()))
    }

    this.handleKeyCommand = (command) => this._handleKeyCommand(command)
    this.onTab = (e) => this._onTab(e)
    this.toggleBlockType = (type) => this._toggleBlockType(type)
    this.toggleInlineStyle = (style) => this._toggleInlineStyle(style)
  }

  _handleKeyCommand(command) {
    const {editorState} = this.state
    const newState = RichUtils.handleKeyCommand(editorState, command)
    if (newState) {
      this.onChange(newState)
      return true
    }
    return false
  }

  _onTab(e) {
    const maxDepth = 4
    this.onChange(RichUtils.onTab(e, this.state.editorState, maxDepth))
  }

  // _toggleBlockType(blockType) {
  //   this.onChange(
  //     RichUtils.toggleBlockType(
  //       this.state.editorState,
  //       blockType
  //     )
  //   )
  // }

  _toggleInlineStyle(inlineStyle) {
    this.onChange(
      RichUtils.toggleInlineStyle(
        this.state.editorState,
        inlineStyle
      )
    )
  }

  getBlockStyle(block) {
    switch (block.getType()) {
      case 'blockquote': return 'RichEditor-blockquote'
      default: return null
    }
  }

  render() {
    const {editorState} = this.state

    // Custom overrides for "code" style.
    const styleMap = {
      CODE: {
        backgroundColor: 'rgba(0, 0, 0, 0.05)',
        fontFamily: '"Inconsolata", "Menlo", "Consolas"',
        fontSize: 16,
        padding: 2
      }
    }

    // If the user changes block type before entering any text, we can
    // either style the placeholder or hide it. Let's just hide it now.
    let className = 'RichEditor-editor'
    let contentState = editorState.getCurrentContent()
    if (!contentState.hasText()) {
      if (contentState.getBlockMap().first().getType() !== 'unstyled') {
        className += ' RichEditor-hidePlaceholder'
      }
    }

    return (
      <div className='RichEditor-root'>
        <InlineStyleControls
          editorState={editorState}
          onToggle={this.toggleInlineStyle}
        />
        <div className={className} onClick={this.focus}>
          <Editor
            blockStyleFn={(block) => this.getBlockStyle(block)}
            customStyleMap={styleMap}
            editorState={editorState}
            handleKeyCommand={this.handleKeyCommand}
            onChange={this.onChange}
            onBlur={this.onBlur}
            onTab={this.onTab}
            placeholder='Mobile Web Prompt'
            ref='editor'
            spellCheck={false}
          />
        </div>
      </div>
    )
  }
}

Draft.propTypes = {
  onBlur: PropTypes.func,
  initialValue: PropTypes.string
}

export default Draft
