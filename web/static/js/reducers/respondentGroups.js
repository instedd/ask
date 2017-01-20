import * as actions from '../actions/respondentGroups'

const initialState = {
  fetching: false,
  items: null,
  surveyId: null,
  invalidRespondents: null
}

export default (state = initialState, action) => {
  switch (action.type) {
    case actions.FETCH_RESPONDENT_GROUPS: return fetchRespondentGroups(state, action)
    case actions.RECEIVE_RESPONDENT_GROUPS: return receiveRespondentGroups(state, action)
    case actions.RECEIVE_RESPONDENT_GROUP: return receiveRespondentGroup(state, action)
    case actions.REMOVE_RESPONDENT_GROUP: return removeRespondentGroup(state, action)
    case actions.INVALID_RESPONDENTS: return receiveInvalids(state, action)
    case actions.CLEAR_INVALIDS: return clearInvalids(state, action)
    case actions.SELECT_CHANNELS: return selectChannels(state, action)
    default: return state
  }
}

const fetchRespondentGroups = (state, action) => {
  const items = state.surveyId == action.surveyId ? state.items : null
  return {
    ...state,
    items,
    fetching: true,
    surveyId: action.surveyId,
    invalidRespondents: null
  }
}

const receiveRespondentGroups = (state, action) => {
  if (state.surveyId != action.surveyId) {
    return state
  }

  const respondentGroups = action.respondentGroups
  return {
    ...state,
    fetching: false,
    items: respondentGroups,
    invalidRespondents: null
  }
}

const receiveRespondentGroup = (state, action) => {
  const group = action.respondentGroup
  return {
    ...state,
    fetching: false,
    items: {
      ...state.items,
      [group.id]: group
    }
  }
}

const removeRespondentGroup = (state, action) => {
  const items = {...state.items}
  delete items[action.id]

  return {
    ...state,
    fetching: false,
    items
  }
}

const receiveInvalids = (state, action) => ({
  ...state,
  invalidRespondents: action.invalidRespondents
})

const clearInvalids = (state, action) => {
  return {
    ...state,
    invalidRespondents: null
  }
}

const selectChannels = (state, action) => {
  return {
    ...state,
    items: {
      ...state.items,
      [action.groupId]: {
        ...state.items[action.groupId],
        channels: action.channels
      }
    }
  }
}

