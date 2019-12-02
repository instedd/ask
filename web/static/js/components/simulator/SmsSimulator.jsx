import React, { Component, PropTypes } from 'react'
import { withRouter } from 'react-router'
import * as test from './testMessages'

class SmsSimulator extends Component {

  state = {
    messages: test.baseMessages()
  }

  handleATMessage = message => {
    const msg = { messageBody: message.messageBody, messageType: 'AT' }
    this.addMessage(msg)
  }

  handleAOMessage = message => {
    const msg = { messageBody: message.messageBody, messageType: 'AO' }
    this.addMessage(msg)
  }

  addMessage = msg => {
    this.setState({ messages: [...this.state.messages, msg] })
  }

  lastMessage = () => {
    if (this.state.messages.length) {
      return this.state.messages.slice(-1)[0]
    } else {
      return null
    }
  }

  // test code: respond on user sent message
  componentDidUpdate() {
    const lastMessage = this.lastMessage()
    if (lastMessage && lastMessage.messageType === 'AT') {
      this.handleAOMessage({ messageBody: 'why you are asking: ' + lastMessage.messageBody + '?' })
    }
  }

  render() {
    const { messages } = this.state
    this.lastMessage()
    return (
      <div className='simulator-container'>
        <div className='col s4 offset-s8'>
          <ChatWindow messages={messages} onSendMessage={this.handleATMessage} chatTitle={'SMS mode'} />
        </div>
      </div>
    )
  }
}

class ChatWindow extends Component {

  render() {
    const { messages, onSendMessage, chatTitle } = this.props

    return (
      <div className='chat-window'>
        <ChatTitle title={chatTitle} />
        <MessagesList messages={messages} />
        <ChatFooter onSendMessage={onSendMessage} />
      </div>
    )
  }
}

ChatWindow.propTypes = {
  messages: PropTypes.array.isRequired,
  chatTitle: PropTypes.string.isRequired,
  onSendMessage: PropTypes.func.isRequired
}

const ChatTitle = props => {
  const { title } = props
  return (
    <div className='chat-header'>{title}</div>
  )
}

ChatTitle.propTypes = {
  title: PropTypes.string.isRequired
}

const MessageBulk = props => {
  const { messages } = props
  const ATMessage = messages[0].messageType === 'AT'
  return (
    <div className={'message-bubble'}>
      {messages.map((message, ix) =>
        <li key={ix} className={ATMessage ? 'at-message' : 'ao-message'}>
          <div className='content-text'>
            {message.messageBody.trim()}
          </div>
        </li>
      )}
    </div>
  )
}

MessageBulk.propTypes = {
  messages: PropTypes.array.isRequired
}

class MessagesList extends Component {
  scrollToBottom = () => {
    window.setTimeout(() => this._messagesBottomDiv.scrollIntoView({ behavior: 'smooth' }), 0)
  }

  componentDidMount() {
    this.scrollToBottom()
  }

  componentDidUpdate() {
    this.scrollToBottom()
  }

  render() {
    const groupBy = (elems, func) => {
      const lastElem = (collection) => (collection[collection.length - 1])

      return elems.reduce(function(groups, elem) {
        const lastGroup = lastElem(groups)
        if (groups.length == 0 || func(lastElem(lastGroup)) != func(elem)) {
          groups.push([elem])
        } else {
          lastGroup.push(elem)
        }
        return groups
      }, [])
    }

    const { messages } = this.props
    const groupedMessages = groupBy(messages, (message) => (message.messageType))

    return (
      <div className='chat-window-body'>
        <ul>
          {groupedMessages.map((messages, ix) =>
            <MessageBulk
              key={`msg-bulk-${ix}`}
              messages={messages}
            />
          )}
        </ul>
        <div style={{ float: 'left', clear: 'both' }} ref={el => { this._messagesBottomDiv = el }} />
      </div>
    )
  }
}

MessagesList.propTypes = {
  messages: PropTypes.array.isRequired
}

class ChatFooter extends Component {
  constructor(props) {
    super(props)

    this.initialState = {
      messageBody: ''
    }

    this.state = this.initialState
  }
  handleChange = event => {
    const { name, value } = event.target
    this.setState({
      [name]: value
    })
  }

  sendMessage = () => {
    this.props.onSendMessage(this.state)
    this.setState(this.initialState)
  }

  sendMessageIfEnterPressed = (event) => {
    if (event.key === 'Enter') {
      event.preventDefault()
      this.sendMessage()
    }
  }

  render() {
    const { messageBody } = this.state
    return (
      <div className='chat-window-input'>
        <input className='chat-input'
          type='text'
          name='messageBody'
          value={messageBody}
          onChange={this.handleChange}
          placeholder='Write your message here'
          onKeyPress={this.sendMessageIfEnterPressed}
        />
        <a onClick={this.sendMessage} className='chat-button'>
          <i className='material-icons'>send</i>
        </a>
      </div>
    )
  }
}

ChatFooter.propTypes = {
  onSendMessage: PropTypes.func.isRequired
}

export default withRouter(SmsSimulator)
