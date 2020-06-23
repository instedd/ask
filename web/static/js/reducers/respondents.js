import * as actions from '../actions/respondents'

const initialState = {
  fetching: false,
  items: null,
  order: [],
  surveyId: null,
  sortBy: null,
  sortAsc: true,
  page: {
    number: 1,
    size: 5,
    totalCount: 0
  },
  filter: null,
  fields: null
}

export default (state = initialState, action) => {
  switch (action.type) {
    case actions.FETCH_RESPONDENTS: return fetchRespondents(state, action)
    case actions.CREATE_RESPONDENT: return createOrUpdateRespondent(state, action)
    case actions.UPDATE_RESPONDENT: return createOrUpdateRespondent(state, action)
    case actions.RECEIVE_RESPONDENTS: return receiveRespondents(state, action)
    default: return state
  }
}

const fetchRespondents = (state, action) => {
  const sameSurvey = state.surveyId == action.surveyId

  const items = sameSurvey ? state.items : null
  return {
    ...state,
    items,
    fetching: true,
    surveyId: action.surveyId,
    filter: action.filter,
    sortBy: sameSurvey ? action.sortBy : null,
    sortAsc: sameSurvey ? action.sortAsc : true,
    page: {
      ...state.page,
      number: action.page
    }
  }
}

const createOrUpdateRespondent = (state, action) => ({
  ...state,
  [action.id]: {
    ...action.respondent
  }
})

const receiveRespondents = (state, action) => ({
  ...state,
  fetching: false,
  items: action.respondents,
  order: action.order,
  page: {
    ...state.page,
    number: action.page,
    totalCount: action.respondentsCount
  },
  fields: action.fields
})
