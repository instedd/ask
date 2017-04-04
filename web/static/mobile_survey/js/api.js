import 'isomorphic-fetch'

export const fetchStep = (mode) => {
  return fetch(`/mobile_survey/get_step?mode=${mode}`, {
    credentials: 'same-origin'
  })
}

export const sendReply = (id, value) => {
  return fetch(`/mobile_survey/send_reply?id=${encodeURIComponent(id)}&value=${encodeURIComponent(value)}`, {
    method: 'POST',
    credentials: 'same-origin'
  })
}
