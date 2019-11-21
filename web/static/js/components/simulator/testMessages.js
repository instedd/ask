export const baseMessages = () => {
  return [
    message('please complete this survey', 'received'),
    message('please be honest', 'received'),
    message('whats your gender?', 'received'),
    message('female', 'sent'),
    message('whats your age?', 'received'),
    message('25', 'sent')
  ]
}

const message = (text, type) => {
  return { messageBody: text, messageType: type }
}
