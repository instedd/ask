import React, {PropTypes} from 'react'

import {
 Editor,
 ContentState,
 convertFromHTML,
 EditorState,
 RichUtils
} from 'draft-js'

// import InlineStyleControls from './InlineStyleControls'
import {stateToHTML} from 'draft-js-export-html'

class Draft extends React.Component {
  constructor(props) {
    super(props)

    this.hasFocus = false

    const blocksFromHTML = convertFromHTML(props.initialValue)
    const state = ContentState.createFromBlockArray(
      blocksFromHTML.contentBlocks,
      blocksFromHTML.entityMap
    )
    this.state = {editorState: EditorState.createWithContent(state)}

    this.focus = () => this.refs.editor.focus()

    this.onFocus = (editorState) => {
      this.hasFocus = true
      this.redraw()
    }

    this.onChange = (editorState) => {
      this.setState({editorState})
      this.redraw()
    }

    this.onBlur = (editorState) => {
      this.hasFocus = false
      this.redraw()
      props.onBlur(stateToHTML(this.state.editorState.getCurrentContent(), {inlineStyles: {UNDERLINE: {element: 'u'}}}))
    }

    this.redraw = () => {
      if (this.state.editorState.getCurrentContent().hasText()) {
        $(this.refs.label).addClass('text')
      } else {
        $(this.refs.label).removeClass('text')
      }

      if (this.hasFocus) {
        $(this.refs.label).addClass('focus')
      } else {
        $(this.refs.label).removeClass('focus')
      }
    }

    this.handleKeyCommand = (command) => this._handleKeyCommand(command)
    this.onTab = (e) => this._onTab(e)
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

  _toggleInlineStyle(inlineStyle) {
    this.onChange(
      RichUtils.toggleInlineStyle(
        this.state.editorState,
        inlineStyle
      )
    )
  }

  render() {
    const {editorState} = this.state

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
        {/*
        <InlineStyleControls
          editorState={editorState}
          onToggle={this.toggleInlineStyle}
        /> */}
        <div className={className} onClick={this.focus}>
          <label ref='label'>
            Mobile web message
          </label>
          <Editor
            editorState={editorState}
            handleKeyCommand={this.handleKeyCommand}
            onChange={this.onChange}
            onFocus={this.onFocus}
            onBlur={this.onBlur}
            onTab={this.onTab}
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
  initialValue: PropTypes.string,
  placeholder: PropTypes.string
}

export default Draft
