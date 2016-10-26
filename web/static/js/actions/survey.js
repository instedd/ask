import * as api from '../api'

export const CHANGE_CUTOFF = 'SURVEY_CHANGE_CUTOFF'
export const CHANGE_QUESTIONNAIRE = 'SURVEY_CHANGE_QUESTIONNAIRE'
export const TOGGLE_DAY = 'SURVEY_TOGGLE_DAY'
export const SET_SCHEDULE_TO = 'SURVEY_SET_SCHEDULE_TO'
export const SET_SCHEDULE_FROM = 'SURVEY_SET_SCHEDULE_FROM'
export const SELECT_CHANNELS = 'SURVEY_SELECT_CHANNELS'
export const UPDATE_RESPONDENTS_COUNT = 'SURVEY_UPDATE_RESPONDENTS_COUNT'
export const SET_STATE = 'SURVEY_SURVEY_SET_STATE'
export const FETCH = 'SURVEY_FETCH'
export const RECEIVE = 'SURVEY_RECEIVE'

export const fetchSurvey = (projectId, id) => (dispatch, getState) => {
  dispatch(fetching(projectId, id))
  return api.fetchSurvey(projectId, id)
    .then(response => {
      dispatch(receive(response.entities.surveys[response.result]))
    })
    .then(() => {
      return getState().survey.data
    })
}

export const fetching = (projectId, id) => ({
  type: FETCH,
  id,
  projectId
})

export const fetch = (projectId, id) => {
  return (dispatch, getState) => {
    if (shouldFetch(getState().survey, projectId, id)) {
      return dispatch(fetchSurvey(projectId, id))
    } else {
      return Promise.resolve(getState().survey.data)
    }
  }
}

export const receive = (survey) => ({
  type: RECEIVE,
  survey
})

export const shouldFetch = (state, projectId, id) => {
  return !state.fetching || !(state.filter && (state.filter.projectId === projectId && state.filter.id === id))
}

export const changeCutoff = (cutoff) => ({
  type: CHANGE_CUTOFF,
  cutoff
})

export const toggleDay = (day) => ({
  type: TOGGLE_DAY,
  day
})

export const setState = (state) => ({
  type: SET_STATE,
  state
})

export const setScheduleFrom = (hour) => ({
  type: SET_SCHEDULE_FROM,
  hour
})

export const selectChannels = (channels) => ({
  type: SELECT_CHANNELS,
  channels
})

export const setScheduleTo = (hour) => ({
  type: SET_SCHEDULE_TO,
  hour
})

export const changeQuestionnaire = (questionnaire) => ({
  type: CHANGE_QUESTIONNAIRE,
  questionnaire
})

export const updateRespondentsCount = (respondentsCount) => ({
  type: UPDATE_RESPONDENTS_COUNT,
  respondentsCount
})
