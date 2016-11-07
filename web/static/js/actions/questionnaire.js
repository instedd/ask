import * as api from '../api'

export const FETCH = 'QUESTIONNAIRE_FETCH'
export const RECEIVE = 'QUESTIONNAIRE_RECEIVE'
export const CHANGE_NAME = 'QUESTIONNAIRE_CHANGE_NAME'
export const TOGGLE_MODE = 'QUESTIONNAIRE_TOGGLE_MODE'
export const ADD_STEP = 'QUESTIONNAIRE_ADD_STEP'
export const DELETE_STEP = 'QUESTIONNAIRE_DELETE_STEP'
export const CHANGE_STEP_TITLE = 'QUESTIONNAIRE_CHANGE_STEP_TITLE'
export const CHANGE_STEP_TYPE = 'QUESTIONNAIRE_CHANGE_STEP_TYPE'
export const CHANGE_STEP_PROMPT_SMS = 'QUESTIONNAIRE_CHANGE_STEP_PROMPT_SMS'
export const CHANGE_STEP_PROMPT_IVR = 'QUESTIONNAIRE_CHANGE_STEP_PROMPT_IVR'
export const CHANGE_STEP_STORE = 'QUESTIONNAIRE_CHANGE_STEP_STORE'
export const ADD_CHOICE = 'QUESTIONNAIRE_ADD_CHOICE'
export const DELETE_CHOICE = 'QUESTIONNAIRE_DELETE_CHOICE'
export const CHANGE_CHOICE = 'QUESTIONNAIRE_CHANGE_CHOICE'

export const AUTOSAVE = [
  CHANGE_NAME,
  TOGGLE_MODE,
  ADD_STEP,
  DELETE_STEP,
  CHANGE_STEP_TITLE,
  CHANGE_STEP_TYPE,
  CHANGE_STEP_PROMPT_SMS,
  CHANGE_STEP_PROMPT_IVR,
  CHANGE_STEP_STORE,
  ADD_CHOICE,
  DELETE_CHOICE,
  CHANGE_CHOICE
]

export const fetchQuestionnaire = (projectId, id) => (dispatch, getState) => {
  dispatch(fetch(projectId, id))
  return api.fetchQuestionnaire(projectId, id)
    .then(response => {
      dispatch(receive(response.entities.questionnaires[response.result]))
    })
    .then(() => {
      return getState().questionnaire.data
    })
}

export const fetch = (projectId, id) => ({
  type: FETCH,
  projectId,
  id
})

export const fetchQuestionnaireIfNeeded = (projectId, id) => {
  return (dispatch, getState) => {
    if (shouldFetch(getState().questionnaire, projectId, id)) {
      return dispatch(fetchQuestionnaire(projectId, id))
    } else {
      return Promise.resolve(getState().questionnaire.data)
    }
  }
}

export const receive = (questionnaire) => ({
  type: RECEIVE,
  data: questionnaire
})

export const shouldFetch = (state, projectId, id) => {
  return !state.fetching || !(state.filter && (state.filter.projectId == projectId && state.filter.id == id))
}

export const addChoice = (stepId) => ({
  type: ADD_CHOICE,
  stepId
})

export const changeChoice = (stepId, index, response, smsValues, ivrValues, skipLogic, autoComplete = false) => ({
  type: CHANGE_CHOICE,
  choiceChange: { index, response, smsValues, ivrValues, skipLogic, autoComplete },
  stepId
})

export const deleteChoice = (stepId, index) => ({
  type: DELETE_CHOICE,
  stepId,
  index
})

export const deleteStep = (stepId) => ({
  type: DELETE_STEP,
  stepId
})

export const changeStepStore = (stepId, newStore) => ({
  type: CHANGE_STEP_STORE,
  stepId,
  newStore
})

export const changeStepPromptSms = (stepId, newPrompt) => ({
  type: CHANGE_STEP_PROMPT_SMS,
  stepId,
  newPrompt
})

export const changeStepPromptIvr = (stepId, newPrompt) => ({
  type: CHANGE_STEP_PROMPT_IVR,
  stepId,
  newPrompt
})

export const changeStepTitle = (stepId, newTitle) => ({
  type: CHANGE_STEP_TITLE,
  stepId,
  newTitle
})

export const changeStepType = (stepId, stepType) => ({
  type: CHANGE_STEP_TYPE,
  stepId,
  stepType
})

export const addStep = () => ({
  type: ADD_STEP
})

export const changeName = (newName) => ({
  type: CHANGE_NAME,
  newName
})

export const toggleMode = (mode) => ({
  type: TOGGLE_MODE,
  mode
})

export const save = () => (dispatch, getState) => {
  const questionnaire = getState().questionnaire.data
  api.updateQuestionnaire(questionnaire.projectId, questionnaire)
}

export const createQuestionnaire = (projectId) => (dispatch) =>
  api.createQuestionnaire(projectId, {name: '', modes: ['sms', 'ivr'], steps: []})
  .then(response => {
    const questionnaire = response.entities.questionnaires[response.result]
    dispatch(fetch(projectId, questionnaire.id))
    dispatch(receive(questionnaire))
    return questionnaire
  })
