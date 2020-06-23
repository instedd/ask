import * as api from '../api'

export const RECEIVE_RESPONDENTS = 'RECEIVE_RESPONDENTS'
export const FETCH_RESPONDENTS = 'FETCH_RESPONDENTS'
export const CREATE_RESPONDENT = 'CREATE_RESPONDENT'
export const UPDATE_RESPONDENT = 'UPDATE_RESPONDENT'
export const RECEIVE_RESPONDENTS_ERROR = 'RECEIVE_RESPONDENTS_ERROR'
export const RECEIVE_RESPONDENTS_STATS = 'RECEIVE_RESPONDENTS_STATS'

export const fetchRespondents = (
  projectId,
  surveyId,
  limit,
  page,
  filter = '',
  sortBy = null,
  sortAsc = true
) => (dispatch, getState) => {
  dispatch(startFetchingRespondents(surveyId, page, filter, sortBy, sortAsc))
  api
    .fetchRespondents(projectId, surveyId, limit, page, filter, sortBy, sortAsc)
    .then((response) => {
      const state = getState().respondents
      const lastFetchResponse =
        state.surveyId == surveyId &&
        state.page.number == page &&
        state.filter == filter &&
        state.sortBy == sortBy &&
        state.sortAsc == sortAsc
      if (lastFetchResponse) {
        dispatch(
          receiveRespondents(
            surveyId,
            page,
            response.entities.respondents || {},
            response.respondentsCount,
            response.result,
            filter,
            sortBy,
            sortAsc,
            response.respondentsFields
          )
        )
      }
    })
}
export const fetchRespondentsStats = (projectId, surveyId) => dispatch => {
  api.fetchRespondentsStats(projectId, surveyId)
    .then(stats => dispatch(receiveRespondentsStats(stats)))
}

export const receiveRespondentsStats = (response) => ({
  type: RECEIVE_RESPONDENTS_STATS,
  response
})

export const receiveRespondents = (surveyId, page, respondents, respondentsCount, order, filter, sortBy, sortAsc, fields) => ({
  type: RECEIVE_RESPONDENTS,
  surveyId,
  page,
  respondents,
  respondentsCount,
  order,
  filter,
  sortBy,
  sortAsc,
  fields
})

export const createRespondent = (response) => ({
  type: CREATE_RESPONDENT,
  id: response.result,
  respondent: response.entities.respondents[response.result]
})

export const updateRespondent = (response) => ({
  type: UPDATE_RESPONDENT,
  id: response.result,
  respondent: response.entities.respondents[response.result]
})

export const updateRespondentsFilter = (projectId, surveyId, filter) => (dispatch, getState) => {
  const { sortBy, sortAsc, page } = getState().respondents
  dispatch(fetchRespondents(projectId, surveyId, page.size, 1, filter, sortBy, sortAsc))
}

export const receiveRespondentsError = (error) => ({
  type: RECEIVE_RESPONDENTS_ERROR,
  error
})

export const startFetchingRespondents = (surveyId, page, filter, sortBy, sortAsc) => ({
  type: FETCH_RESPONDENTS,
  surveyId,
  page,
  filter,
  sortBy,
  sortAsc
})

export const sortRespondentsBy = (projectId, surveyId, newSortBy) => (dispatch, getState) => {
  const { page, filter, sortBy, sortAsc } = getState().respondents
  const newSortAsc = sortBy == newSortBy ? !sortAsc : true
  dispatch(fetchRespondents(projectId, surveyId, page.size, 1, filter, newSortBy, newSortAsc))
}
