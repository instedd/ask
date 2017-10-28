// @flow
import * as api from '../api'
import each from 'lodash/each'
import { stepStoreValues } from '../reducers/questionnaire'
import * as surveysActions from './surveys'

export const CHANGE_CUTOFF = 'SURVEY_CHANGE_CUTOFF'
export const CHANGE_QUOTA = 'SURVEY_CHANGE_QUOTA'
export const CHANGE_COMPARISON_RATIO = 'SURVEY_CHANGE_COMPARISON_RATIO'
export const CHANGE_QUESTIONNAIRE = 'SURVEY_CHANGE_QUESTIONNAIRE'
export const CHANGE_NAME = 'SURVEY_CHANGE_NAME'
export const TOGGLE_DAY = 'SURVEY_TOGGLE_DAY'
export const SET_SCHEDULE_TO = 'SURVEY_SET_SCHEDULE_TO'
export const SET_SCHEDULE_FROM = 'SURVEY_SET_SCHEDULE_FROM'
export const ADD_SCHEDULE_BLOCKED_DAY = 'SURVEY_ADD_SCHEDULE_BLOCKED_DAY'
export const REMOVE_SCHEDULE_BLOCKED_DAY = 'SURVEY_REMOVE_SCHEDULE_BLOCKED_DAY'
export const CLEAR_SCHEDULE_BLOCKED_DAYS = 'SURVEY_CLEAR_SCHEDULE_BLOCKED_DAYS'
export const SELECT_MODE = 'SURVEY_SELECT_MODE'
export const CHANGE_MODE_COMPARISON = 'SURVEY_CHANGE_MODE_COMPARISON'
export const CHANGE_QUESTIONNAIRE_COMPARISON = 'SURVEY_CHANGE_QUESTIONNAIRE_COMPARISON'
export const UPDATE_RESPONDENTS_COUNT = 'SURVEY_UPDATE_RESPONDENTS_COUNT'
export const SET_STATE = 'SURVEY_SURVEY_SET_STATE'
export const FETCH = 'SURVEY_FETCH'
export const RECEIVE = 'SURVEY_RECEIVE'
export const SAVING = 'SURVEY_SAVING'
export const SAVED = 'SURVEY_SAVED'
export const SET_TIMEZONE = 'SURVEY_SET_TIMEZONE'
export const SET_QUOTA_VARS = 'SURVEY_SET_QUOTA_VARS'
export const CHANGE_SMS_RETRY_CONFIGURATION = 'SURVEY_CHANGE_SMS_RETRY_CONFIGURATION'
export const CHANGE_IVR_RETRY_CONFIGURATION = 'SURVEY_CHANGE_IVR_RETRY_CONFIGURATION'
export const CHANGE_MOBILEWEB_RETRY_CONFIGURATION = 'SURVEY_CHANGE_MOBILEWEB_RETRY_CONFIGURATION'
export const CHANGE_FALLBACK_DELAY = 'SURVEY_CHANGE_FALLBACK_DELAY'
export const TOGGLE_COUNT_PARTIAL_RESULTS = 'SURVEY_TOGGLE_COUNT_PARTIAL_RESULTS'
export const RECEIVE_LINK = 'SURVEY_RECEIVE_LINK'
export const REFRESH_LINK = 'SURVEY_REFRESH_LINK'
export const DELETE_LINK = 'SURVEY_DELETE_LINK'

export const createSurvey = (projectId: number) => (dispatch: Function, getState: () => Store) =>
  api.createSurvey(projectId).then(response => {
    const survey = response.result
    dispatch(fetch(projectId, survey.id))
    dispatch(receive(survey))
    return survey
  })

export const fetchSurvey = (projectId: number, id: number) => (dispatch: Function, getState: () => Store): Survey => {
  dispatch(fetch(projectId, id))
  return api.fetchSurvey(projectId, id)
    .then(response => {
      dispatch(receive(response.entities.surveys[response.result]))
    })
    .then(() => {
      return getState().survey.data
    })
}

export const fetch = (projectId: number, id: number): FilteredAction => ({
  type: FETCH,
  id,
  projectId
})

export const fetchSurveyIfNeeded = (projectId: number, id: number) => (dispatch: Function, getState: () => Store): Promise<?Survey> => {
  if (shouldFetch(getState().survey, projectId, id)) {
    return dispatch(fetchSurvey(projectId, id))
  } else {
    return Promise.resolve(getState().survey.data)
  }
}

export const receive = (survey: Survey) => ({
  type: RECEIVE,
  data: survey
})

export const shouldFetch = (state: DataStore<Survey>, projectId: number, id: number) => {
  return !state.fetching || !(state.filter && (state.filter.projectId == projectId && state.filter.id == id))
}

export const changeCutoff = (cutoff: string) => ({
  type: CHANGE_CUTOFF,
  cutoff
})

export const comparisonRatioChange = (questionnaireId: number, mode: string[], ratio: number) => ({
  type: CHANGE_COMPARISON_RATIO,
  questionnaireId,
  mode,
  ratio
})

export const quotaChange = (condition: Condition[], quota: number) => ({
  type: CHANGE_QUOTA,
  condition,
  quota
})

export const toggleDay = (day: string) => ({
  type: TOGGLE_DAY,
  day
})

export const setQuotaVars = (vars: QuotaVar[], questionnaire: Questionnaire) => ({
  type: SET_QUOTA_VARS,
  vars,
  options: optionsFrom(vars, questionnaire)
})

const optionsFrom = (storeVars: QuotaVar[], questionnaire: Questionnaire) => {
  const storeValues = stepStoreValues(questionnaire)
  let options = {}

  each(storeVars, (storeVar) => {
    options[storeVar.var] = storeValues[storeVar.var]
  })
  return options
}

export const setState = (state: string) => ({
  type: SET_STATE,
  state
})

export const changeName = (newName: string) => ({
  type: CHANGE_NAME,
  newName
})

export const setScheduleFrom = (hour: string, nextHour: string) => ({
  type: SET_SCHEDULE_FROM,
  hour,
  nextHour
})

export const setScheduleTo = (hour: string, previousHour: string) => ({
  type: SET_SCHEDULE_TO,
  hour,
  previousHour
})

export const clearBlockedDays = () => ({
  type: CLEAR_SCHEDULE_BLOCKED_DAYS
})

export const addScheduleBlockedDay = (day: string) => ({
  type: ADD_SCHEDULE_BLOCKED_DAY,
  day
})

export const removeScheduleBlockedDay = (day: string) => ({
  type: REMOVE_SCHEDULE_BLOCKED_DAY,
  day
})

export const selectMode = (mode: string[]) => ({
  type: SELECT_MODE,
  mode
})

export const changeModeComparison = () => ({
  type: CHANGE_MODE_COMPARISON
})

export const toggleCountPartialResults = () => ({
  type: TOGGLE_COUNT_PARTIAL_RESULTS
})

export const changeQuestionnaireComparison = () => ({
  type: CHANGE_QUESTIONNAIRE_COMPARISON
})

export const changeQuestionnaire = (questionnaire: number, questionnaires: any) => ({
  type: CHANGE_QUESTIONNAIRE,
  questionnaire,
  questionnaires
})

export const updateRespondentsCount = (respondentsCount: string) => ({
  type: UPDATE_RESPONDENTS_COUNT,
  respondentsCount
})

export const setTimezone = (timezone: string) => ({
  type: SET_TIMEZONE,
  timezone
})

export const changeSmsRetryConfiguration = (smsRetryConfiguration: string) => ({
  type: CHANGE_SMS_RETRY_CONFIGURATION,
  smsRetryConfiguration
})

export const changeIvrRetryConfiguration = (ivrRetryConfiguration: string) => ({
  type: CHANGE_IVR_RETRY_CONFIGURATION,
  ivrRetryConfiguration
})

export const changeMobileWebRetryConfiguration = (mobilewebRetryConfiguration: string) => ({
  type: CHANGE_MOBILEWEB_RETRY_CONFIGURATION,
  mobilewebRetryConfiguration
})

export const deleteSurvey = (survey: Survey) => (dispatch: Function) => {
  api.deleteSurvey(survey.projectId, survey)
    .then(response => {
      return dispatch(surveysActions.deleted(survey))
    })
}

export const changeFallbackDelay = (fallbackDelay: string) => ({
  type: CHANGE_FALLBACK_DELAY,
  fallbackDelay
})

export const saving = () => ({
  type: SAVING
})

export const saved = (survey: Survey) => ({
  type: SAVED,
  data: survey
})

export const save = () => (dispatch: Function, getState: () => Store) => {
  const survey = getState().survey.data
  if (!survey) return
  dispatch(saving())
  api.updateSurvey(survey.projectId, survey)
    .then(response => {
      return dispatch(saved(response.entities.surveys[response.result]))
    })
}

export const receiveLink = (link: Link) => ({
  type: RECEIVE_LINK,
  link
})

export const refreshLink = (originalLink: Link, newLink: Link) => ({
  type: REFRESH_LINK,
  originalLink,
  newLink
})

export const deleteLink = (link: Link) => ({
  type: DELETE_LINK,
  link
})

export const createResultsLink = (projectId: number, surveyId: number) => (dispatch: Function) => {
  api.createResultsLink(projectId, surveyId)
    .then(response => {
      return dispatch(receiveLink(response))
    })
}

export const createIncentivesLink = (projectId: number, surveyId: number) => (dispatch: Function) => {
  api.createIncentivesLink(projectId, surveyId)
    .then(response => {
      return dispatch(receiveLink(response))
    })
}

export const createInteractionsLink = (projectId: number, surveyId: number) => (dispatch: Function) => {
  api.createInteractionsLink(projectId, surveyId)
    .then(response => {
      return dispatch(receiveLink(response))
    })
}

export const createDispositionHistoryLink = (projectId: number, surveyId: number) => (dispatch: Function) => {
  api.createDispositionHistoryLink(projectId, surveyId)
    .then(response => {
      return dispatch(receiveLink(response))
    })
}

export const refreshResultsLink = (projectId: number, surveyId: number, link: Link) => (dispatch: Function) => {
  api.refreshResultsLink(projectId, surveyId)
    .then(response => {
      return dispatch(refreshLink(link, response))
    })
}

export const refreshIncentivesLink = (projectId: number, surveyId: number, link: Link) => (dispatch: Function) => {
  api.refreshIncentivesLink(projectId, surveyId)
    .then(response => {
      return dispatch(refreshLink(link, response))
    })
}

export const refreshInteractionsLink = (projectId: number, surveyId: number, link: Link) => (dispatch: Function) => {
  api.refreshInteractionsLink(projectId, surveyId)
    .then(response => {
      return dispatch(refreshLink(link, response))
    })
}

export const refreshDispositionHistoryLink = (projectId: number, surveyId: number, link: Link) => (dispatch: Function) => {
  api.refreshDispositionHistoryLink(projectId, surveyId)
    .then(response => {
      return dispatch(refreshLink(link, response))
    })
}

export const deleteResultsLink = (projectId: number, surveyId: number, link: Link) => (dispatch: Function) => {
  api.deleteResultsLink(projectId, surveyId)
    .then(response => {
      return dispatch(deleteLink(link))
    })
}

export const deleteIncentivesLink = (projectId: number, surveyId: number, link: Link) => (dispatch: Function) => {
  api.deleteIncentivesLink(projectId, surveyId)
    .then(response => {
      return dispatch(deleteLink(link))
    })
}

export const deleteInteractionsLink = (projectId: number, surveyId: number, link: Link) => (dispatch: Function) => {
  api.deleteInteractionsLink(projectId, surveyId)
    .then(response => {
      return dispatch(deleteLink(link))
    })
}

export const deleteDispositionHistoryLink = (projectId: number, surveyId: number, link: Link) => (dispatch: Function) => {
  api.deleteDispositionHistoryLink(projectId, surveyId)
    .then(response => {
      return dispatch(deleteLink(link))
    })
}
