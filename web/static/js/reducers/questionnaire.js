import filter from 'lodash/filter'
import findIndex from 'lodash/findIndex'
import isEqual from 'lodash/isEqual'
import toInteger from 'lodash/toInteger'
import * as actions from '../actions/questionnaire'
import uuid from 'node-uuid'

const defaultState = {
  fetching: false,
  filter: null,
  data: null
}

export default (state, action) => {
  if (state === undefined) {
    return defaultState
  }

  switch (action.type) {
    case actions.FETCH: return fetch(state, action)
    case actions.RECEIVE: return receive(state, action)
    case actions.NEW: return newQuestionnaire(state, action)
  }

  return {
    ...state,
    data: state.data == null ? null : dataReducer(state.data, action)
  }
}

const dataReducer = (state, action) => {
  switch (action.type) {
    case actions.CHANGE_NAME: return changeName(state, action)
    case actions.CHANGE_MODES: return changeModes(state, action)
  }

  return {
    ...state,
    steps: stepsReducer(state.steps, action)
  }
}

const stepsReducer = (state, action) => {
  switch (action.type) {
    case actions.ADD_STEP: return addStep(state, action)
    case actions.CHANGE_STEP_TITLE: return changeStepTitle(state, action)
    case actions.CHANGE_STEP_PROMPT_SMS: return changeStepSmsPrompt(state, action)
    case actions.CHANGE_STEP_STORE: return changeStepStore(state, action)
    case actions.DELETE_STEP: return deleteStep(state, action)
    case actions.ADD_CHOICE: return addChoice(state, action)
    case actions.DELETE_CHOICE: return deleteChoice(state, action)
    case actions.CHANGE_CHOICE: return changeChoice(state, action)
  }

  return state
}

const addChoice = (state, action) => {
  return updateChoices(state, action.stepId, choices => {
    choices.push({
      value: '',
      responses: []
    })
    return choices
  })
}

const deleteChoice = (state, action) => {
  return updateChoices(state, action.stepId, choices => choices.splice(action.index, 1))
}

const changeChoice = (state, action) => {
  return updateChoices(state, action.stepId, (choices) => {
    choices[action.choiceChange.index] = {
      ...choices[action.choiceChange.index],
      value: action.choiceChange.value,
      responses: action.choiceChange.responses.split(',').map((r) => r.trim())
    }
    return choices
  })
}

const updateChoices = (state, stepId, func) => {
  return changeStep(state, stepId, step => {
    step.choices = func(step.choices.slice())
  })
}

const deleteStep = (state, action) => {
  return filter(state, s => s.id !== action.stepId)
}

const changeStep = (state, stepId, func) => {
  let newState = state.slice()
  const stepIndex = findIndex(newState, s => s.id === stepId)

  func(newState[stepIndex])
  return newState
}

const changeStepSmsPrompt = (state, action) => {
  return changeStep(state, action.stepId, step => {
    step.prompt.sms = action.newPrompt
  })
}

const changeStepTitle = (state, action) => {
  return changeStep(state, action.stepId, step => { step.title = action.newTitle })
}

const changeStepStore = (state, action) => {
  return changeStep(state, action.stepId, step => { step.store = action.newStore })
}

const buildFilter = (projectId, questionnaireId) => ({
  projectId: toInteger(projectId),
  questionnaireId: questionnaireId == null ? null : toInteger(questionnaireId)
})

const newQuestionnaire = (state, action) => {
  return {
    ...state,
    fetching: false,
    filter: buildFilter(action.projectId, null),
    data: {
      id: null,
      name: '',
      modes: ['SMS'],
      projectId: action.projectId,
      steps: []
    }
  }
}

const addStep = (state, action) => {
  return [
    ...state,
    action.newStep
  ]
}

export const buildNewStep = (stepType) => ({
  id: uuid.v4(),
  type: stepType,
  title: '',
  store: '',
  prompt: {
    sms: ''
  },
  choices: []
})

const changeModes = (state, action) => {
  return {
    ...state,
    modes: action.newModes.split(',')
  }
}

const changeName = (state, action) => {
  return {
    ...state,
    name: action.newName
  }
}

const receive = (state, action) => {
  const questionnaire = action.questionnaire
  const dataFilter = buildFilter(questionnaire.projectId, questionnaire.id)

  if (isEqual(state.filter, dataFilter)) {
    return {
      ...state,
      fetching: false,
      data: questionnaire
    }
  }

  return state
}

const fetch = (state, action) => {
  const newFilter = buildFilter(action.projectId, action.questionnaireId)

  let newData = null

  if (isEqual(state.filter, newFilter)) {
    newData = state.data
  }

  return {
    ...state,
    fetching: true,
    filter: newFilter,
    data: newData
  }
}
