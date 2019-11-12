import React, { Component, PropTypes } from 'react'
import { connect } from 'react-redux'
import { withRouter } from 'react-router'

class SmsSimulator extends Component{

    state = {
        messages: []
    }

    handleUserSentMessage = message => {
        const msg = {messageBody: message.messageBody, messageType: "sent"}
        this.addMessage(msg)
    }

    handleBotSentMessage = message => {
        const msg = {messageBody: message.messageBody, messageType: "received"}
        this.addMessage(msg)
    }

    addMessage = msg => {
        this.setState({messages: [...this.state.messages, msg]})
    }

    lastMessage = () => {
        if(this.state.messages.length) {
            return this.state.messages.slice(-1)[0]
        }
        else {
            return null
        }
    }

    componentDidUpdate() {
        const lastMessage = this.lastMessage()
        if (lastMessage && lastMessage.messageType === "sent"){
            this.handleBotSentMessage({messageBody: "why you are asking: " + lastMessage.messageBody + "?"})
        }
    }

    render(){
        const {messages} = this.state
        this.lastMessage()
        return(
            <div>
                <ChatWindow messages={messages} onSendMessage={this.handleUserSentMessage} chatTitle={"SMS mode"}/>
            </div>
        )
    }
}

class ChatWindow extends Component {

    render() {
        const {messages, onSendMessage, chatTitle} = this.props

        return(
            <div className="chat-window">
                <ChatTitle title={chatTitle} />
                <MessagesList messages={messages} />
                <ChatFooter onSendMessage={onSendMessage} />
            </div>
        )
    }
}
const ChatTitle = props => {
    const {title} = props
    return(
        <div className="chat-header">{title}</div>
    )
}

const MessageBulk = props =>{
    const {message} = props
    const sentMessage = message.messageType === "sent"
    return (
        <li className={"message-bubble " + (sentMessage ? "message-sent" : "message-received")}>
            {message.messageBody.trim()}
        </li>
    )
}

class MessagesList extends Component {
    scrollToBottom = () => {
        window.setTimeout(() => this._messagesBottomDiv.scrollIntoView({ behavior: "smooth" }), 0)
    }

    componentDidMount() {
        this.scrollToBottom()
    }

    componentDidUpdate() {
        this.scrollToBottom()
    }

    render(){
        const { messages } = this.props

        const messageList = messages.map((message, index) => {
            return (
                <MessageBulk key={`msg-bulk-${index}`} message={message}/>
            )
        })
        return (
            <div className="chat-window-body">
                <ul>{messageList}</ul>
                <div style={{ float: "left", clear: "both" }}
                     ref={(el) => { this._messagesBottomDiv = el; }}>
                </div>
            </div>
        )
    }
}

class ChatFooter extends Component {
    constructor(props){
        super(props)

        this.initialState = {
            messageBody: ''
        }

        this.state = this.initialState
    }
    handleChange = event => {
        const {name, value} = event.target
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

    render(){
        const {messageBody} = this.state
        return(
            <div className="chat-window-input">
                <input className="chat-input"
                    type="text"
                    name="messageBody"
                    value={messageBody}
                    onChange={this.handleChange}
                    placeholder="Type message here"
                    onKeyPress={this.sendMessageIfEnterPressed}
                />
                <a onClick={this.sendMessage} className="chat-button">SEND</a>
            </div>
        )
    }
}

// const mapStateToProps = (state) => {}
// export default withRouter(connect(mapStateToProps)(SmsSimulator))

export default withRouter(SmsSimulator)
