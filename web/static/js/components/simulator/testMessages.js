export const baseMessages = () => {
  return [
    message('please complete this survey', 'AO'),
    message('please be honest', 'AO'),
    message('whats your gender?', 'AO'),
    message('female', 'AT'),
    message('whats your age?', 'AO'),
    message('25', 'AT')
  ]
}

const message = (text, type) => {
  return { messageBody: text, messageType: type }
}
