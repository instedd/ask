// @flow
import filter from 'lodash/filter'
import findIndex from 'lodash/findIndex'
import reduce from 'lodash/reduce'
import map from 'lodash/map'
import concat from 'lodash/concat'
import * as actions from '../actions/questionnaire'
import uuid from 'node-uuid'
import fetchReducer from './fetch'

const dataReducer = (state: Questionnaire, action): Questionnaire => {
  switch (action.type) {
    case actions.CHANGE_NAME: return changeName(state, action)
    case actions.TOGGLE_MODE: return toggleMode(state, action)
    case actions.ADD_LANGUAGE: return addLanguage(state, action)
    case actions.REMOVE_LANGUAGE: return removeLanguage(state, action)
    case actions.SET_DEFAULT_LANGUAGE: return setDefaultLanguage(state, action)
    case actions.REORDER_LANGUAGES: return reorderLanguages(state, action)
    default: return steps(state, action)
  }
}

const steps = (state, action) => {
  // Up to now we've been assuming that all content was under corresponding 'en' keys,
  // now that languages can be added and removed and default language can be
  // set to whatever the user wants, that assumption is not safe anymore.
  // Moreover, most of the actions that the stepsReducer needs to handle will need
  // questionnaire level knowledge, namely the set of all questionnaire languages
  // and the questionnaire's default language.
  // Given we are on a tight schedule, I chose to pass the questionnaire down
  // to the stepsReducer in a separate variable so there are no conflicts.
  // That's the `state` argument added to the stepsReducer call.
  // Multilanguage has impacted the application much more thoroughly than we had
  // anticipated, this is a compromise solution that should be revised.
  const newSteps = state.steps == null ? [] : stepsReducer(state.steps, action, state)

  if (newSteps !== state.steps) {
    return {
      ...state,
      steps: newSteps
    }
  } else {
    return state
  }
}

const stepsReducer = (state, action, quiz: Questionnaire) => {
  switch (action.type) {
    case actions.ADD_STEP: return addStep(state, action)
    case actions.CHANGE_STEP_TITLE: return changeStepTitle(state, action)
    case actions.CHANGE_STEP_TYPE: return changeStepType(state, action)
    case actions.CHANGE_STEP_PROMPT_SMS: return changeStepSmsPrompt(state, action, quiz)
    case actions.CHANGE_STEP_PROMPT_IVR: return changeStepIvrPrompt(state, action, quiz)
    case actions.CHANGE_STEP_AUDIO_ID_IVR: return changeStepIvrAudioId(state, action, quiz)
    case actions.CHANGE_STEP_STORE: return changeStepStore(state, action)
    case actions.DELETE_STEP: return deleteStep(state, action)
    case actions.ADD_CHOICE: return addChoice(state, action)
    case actions.DELETE_CHOICE: return deleteChoice(state, action)
    case actions.CHANGE_CHOICE: return changeChoice(state, action, quiz)
    case actions.CHANGE_NUMERIC_RANGES: return changeNumericRanges(state, action)
    case actions.CHANGE_RANGE_SKIP_LOGIC: return changeRangeSkipLogic(state, action)
  }

  return state
}

const addChoice = (state, action) => {
  return changeStep(state, action.stepId, step => ({
    ...step,
    choices: [
      ...step.choices,
      {
        value: '',
        responses: {
          'en': {
            sms: [],
            ivr: []
          }
        },
        skipLogic: null
      }
    ]
  }))
}

const deleteChoice = (state, action) => {
  return changeStep(state, action.stepId, (step) => ({
    ...step,
    choices: [
      ...step.choices.slice(0, action.index),
      ...step.choices.slice(action.index + 1)
    ]
  }))
}

// TODO: now we're assuming that the choice content being changed is
// in the default language. Revisit this if we ever allow users to
// directly edit content in all languages directly from the UI.
const changeChoice = (state, action, quiz: Questionnaire) => {
  let smsValues = action.choiceChange.smsValues
  let ivrValues = action.choiceChange.ivrValues
  if (action.choiceChange.autoComplete && smsValues == '' && ivrValues == '') {
    [smsValues, ivrValues] = autoComplete(state, action.choiceChange.response, quiz)
  }
  let ivrArrayValues = splitValues(ivrValues)
  return changeStep(state, action.stepId, (step) => ({
    ...step,
    choices: [
      ...step.choices.slice(0, action.choiceChange.index),
      {
        ...step.choices[action.choiceChange.index],
        value: action.choiceChange.response,
        responses: {
          ...step.choices[action.choiceChange.index].responses,
          'en': {
            ...step.choices[action.choiceChange.index].responses[quiz.defaultLanguage],
            sms: splitValues(smsValues),
            ivr: ivrArrayValues
          }
        },
        skipLogic: action.choiceChange.skipLogic
      },
      ...step.choices.slice(action.choiceChange.index + 1)
    ]
  }))
}

const autoComplete = (state, value, quiz: Questionnaire) => {
  let setted = false

  let smsValues = ''
  let ivrValues = ''

  state.forEach((step) => {
    if ((step.type === 'multiple-choice') && !setted) {
      step.choices.forEach((choice) => {
        if (choice.value == value && !setted) {
          setted = true
          smsValues = choice.responses[quiz.defaultLanguage].sms.join(',')
          ivrValues = choice.responses[quiz.defaultLanguage].ivr.join(',')
        }
      })
    }
  })
  return [smsValues, ivrValues]
}

const splitValues = (values) => {
  return values.split(',').map((r) => r.trim()).filter(r => r.length != 0)
}

const deleteStep = (state, action) => {
  return filter(state, s => s.id != action.stepId)
}

function changeStep<T: Step>(state, stepId, func: (step: Object) => T) {
  const stepIndex = findIndex(state, s => s.id == stepId)

  return [
    ...state.slice(0, stepIndex),
    func(state[stepIndex]),
    ...state.slice(stepIndex + 1)
  ]
}

type ActionChangeStepSmsPrompt = {
  stepId: string,
  newPrompt: string
};

const changeStepSmsPrompt = (state, action: ActionChangeStepSmsPrompt, quiz: Questionnaire): Step[] => {
  return changeStep(state, action.stepId, step => ({
    ...step,
    prompt: {
      ...step.prompt,
      [quiz.defaultLanguage]: {
        ...step.prompt[quiz.defaultLanguage],
        sms: action.newPrompt
      }
    }
  }))
}

const changeStepIvrPrompt = (state, action, quiz: Questionnaire) => {
  return changeStep(state, action.stepId, step => ({
    ...step,
    prompt: {
      ...step.prompt,
      [quiz.defaultLanguage]: {
        ...step.prompt[quiz.defaultLanguage],
        ivr: {
          ...step.prompt[quiz.defaultLanguage].ivr,
          text: action.newPrompt.text,
          audioSource: action.newPrompt.audioSource
        }
      }
    }
  }))
}

const changeStepIvrAudioId = (state, action, quiz: Questionnaire) => {
  return changeStep(state, action.stepId, step => ({
    ...step,
    prompt: {
      ...step.prompt,
      [quiz.defaultLanguage]: {
        ...step.prompt[quiz.defaultLanguage],
        ivr: {
          ...step.prompt[quiz.defaultLanguage].ivr,
          audioId: action.newId,
          audioSource: 'upload'
        }
      }
    }
  }))
}

const changeStepTitle = (state, action) => {
  return changeStep(state, action.stepId, step => ({
    ...step,
    title: action.newTitle
  }))
}

const clearTypeProperties = (step) => {
  let commons = ['id', 'title', 'prompt', 'store']
  let baseStep = {}
  for (let prop in step) {
    if (commons.includes(prop)) {
      baseStep[prop] = step[prop]
    }
  }

  return baseStep
}

const changeStepType = (state, action) => {
  switch (action.stepType) {
    case 'multiple-choice':
      return changeStep(state, action.stepId, step => {
        let baseStep = clearTypeProperties(step)
        return {
          ...baseStep,
          type: action.stepType,
          choices: []
        }
      })
    case 'numeric':
      return changeStep(state, action.stepId, step => {
        let baseStep = clearTypeProperties(step)
        return {
          ...baseStep,
          type: action.stepType,
          minValue: null,
          maxValue: null,
          rangesDelimiters: null,
          ranges: [{from: null, to: null, skipLogic: null}]
        }
      })
    default:
      throw new Error(`unknown step type: ${action.stepType}`)
  }
}

const changeStepStore = (state, action) => {
  return changeStep(state, action.stepId, step => ({
    ...step,
    store: action.newStore
  }))
}

const addStep = (state, action) => {
  return [
    ...state,
    newMultipleChoiceStep()
  ]
}

const newLanguageSelectionStep = (first: string, second: string): LanguageSelectionStep => {
  return {
    id: uuid.v4(),
    type: 'language-selection',
    title: 'Language selection',
    store: '',
    prompt: {
      'en': {
        sms: '',
        ivr: {
          text: '',
          audioSource: 'tts'
        }
      }
    },
    languageChoices: [null, first, second]
  }
}

const newMultipleChoiceStep = () => {
  return {
    id: uuid.v4(),
    type: 'multiple-choice',
    title: '',
    store: '',
    prompt: {
      'en': {
        sms: '',
        ivr: {
          text: '',
          audioSource: 'tts'
        }
      }
    },
    choices: []
  }
}

const toggleMode = (state, action) => {
  let modes = state.modes
  if (modes.indexOf(action.mode) == -1) {
    modes = modes.slice()
    modes.push(action.mode)
  } else {
    modes = modes.filter(mode => mode != action.mode)
  }
  return {
    ...state,
    modes
  }
}

type ActionChangeName = {
  newName: string
};

const changeName = (state: Questionnaire, action: ActionChangeName): Questionnaire => {
  return {
    ...state,
    name: action.newName
  }
}

const addLanguage = (state, action) => {
  if (state.languages.indexOf(action.language) == -1) {
    let steps
    if (state.languages.length == 1) {
      steps = addLanguageSelectionStep(state, action)
    } else {
      steps = addOptionToLanguageSelectionStep(state, action.language)
    }
    return {
      ...state,
      steps: steps,
      languages: [...state.languages, action.language]
    }
  } else {
    return state
  }
}

const removeLanguage = (state, action) => {
  const indexToDelete = state.languages.indexOf(action.language)
  if (indexToDelete != -1) {
    const newLanguages = [...state.languages.slice(0, indexToDelete), ...state.languages.slice(indexToDelete + 1)]
    let newSteps = removeOptionFromLanguageSelectionStep(state, action.language)

    // If only one language remains, remove the language-selection
    // step (should be the first one)
    if (newLanguages.length == 1 && state.languages.length > 1) {
      newSteps = newSteps.slice(1)
    }

    return {
      ...state,
      steps: newSteps,
      languages: newLanguages
    }
  } else {
    return state
  }
}

const reorderLanguages = (state, action) => {
  let languageSelectionStep = state.steps[0]

  if (languageSelectionStep.type === 'language-selection') {
    let choices = languageSelectionStep.languageChoices

    var index = choices.indexOf(action.language)
    if (index > -1) {
      choices.splice(index, 1)
      choices.splice(action.index, 0, action.language)
    }

    return {
      ...state,
      steps: changeStep(state.steps, state.steps[0].id, (step) => ({
        ...step,
        languageChoices: choices
      }))
    }
  } else {
    return state
  }
}

const addOptionToLanguageSelectionStep = (state, language) => {
  return changeStep(state.steps, state.steps[0].id, (step) => ({
    ...step,
    languageChoices: [
      ...step.languageChoices,
      language
    ]
  }))
}

const removeOptionFromLanguageSelectionStep = (state, language) => {
  const languageSelectionStep = state.steps[0]

  if (languageSelectionStep.type === 'language-selection') {
    const choices = languageSelectionStep.languageChoices
    const index = choices.indexOf(language)

    const newLanguages = [...choices.slice(0, index), ...choices.slice(index + 1)]

    return changeStep(state.steps, languageSelectionStep.id, (step) => ({
      ...step,
      languageChoices: newLanguages
    }))
  } else {
    return state.steps
  }
}

const addLanguageSelectionStep = (state, action) => {
  return [
    newLanguageSelectionStep(state.languages[0], action.language),
    ...state.steps
  ]
}

const setDefaultLanguage = (state, action) => {
  console.log(state.steps)
  console.log(action)

  return {
    ...state,
    defaultLanguage: action.language
  }
}

type ValidationState = {
  data: Questionnaire,
  errors: { [path: string]: string[] }
};

const validateReducer = (reducer) => {
  return (state: ValidationState, action: any) => {
    const newState = reducer(state, action)
    validate(newState)
    return newState
  }
}

const validate = (state: ValidationState) => {
  if (!state.data) return
  state.errors = {}
  const context = {
    sms: state.data.modes.indexOf('sms') != -1,
    ivr: state.data.modes.indexOf('ivr') != -1,
    defaultLanguage: state.data.defaultLanguage,
    languages: state.data.languages,
    errors: state.errors
  }

  validateSteps('steps', state.data.steps, context)
}

const validateSteps = (path, steps, context) => {
  for (let i = 0; i < steps.length; i++) {
    validateStep(`${path}[${i}]`, steps[i], context)
  }
}

const validateStep = (path, step, context) => {
  if (context.sms &&
      (!step.prompt[context.defaultLanguage] ||
      !step.prompt[context.defaultLanguage].sms ||
      isBlank(step.prompt[context.defaultLanguage].sms))) {
    addError(context, `${path}.prompt.sms`, 'SMS prompt must not be blank')
  }

  if (context.ivr &&
      step.prompt[context.defaultLanguage] &&
      step.prompt[context.defaultLanguage].ivr &&
      step.prompt[context.defaultLanguage].ivr.audioSource == 'tts' &&
      isBlank(step.prompt[context.defaultLanguage].ivr.text)) {
    addError(context, `${path}.prompt.ivr.text`, 'Voice prompt must not be blank')
  }

  if (step.type === 'multiple-choice') {
    validateChoices(`${path}.choices`, step.choices, context)
  }
}

const validateChoices = (path, choices: Choice[], context) => {
  if (choices.length < 2) {
    addError(context, path, 'Must have at least two responses')
  }

  for (let i = 0; i < choices.length; i++) {
    validateChoice(`${path}[${i}]`, choices[i], context)
  }

  const values = []
  let sms = []
  let ivr = []
  for (let i = 0; i < choices.length; i++) {
    let choice = choices[i]
    if (values.includes(choice.value)) {
      addError(context, `${path}[${i}].value`, 'Value already used in a previous response')
    }

    if (choice.responses[context.defaultLanguage] && choice.responses[context.defaultLanguage].sms) {
      for (let choiceSms of choice.responses[context.defaultLanguage].sms) {
        if (sms.includes(choiceSms)) {
          addError(context, `${path}[${i}].sms`, `Value "${choiceSms}" already used in a previous response`)
        }
      }
      sms.push(...choice.responses[context.defaultLanguage].sms)
    }

    if (choice.responses[context.defaultLanguage] && choice.responses[context.defaultLanguage].ivr) {
      for (let choiceIvr of choice.responses[context.defaultLanguage].ivr) {
        if (ivr.includes(choiceIvr)) {
          addError(context, `${path}[${i}].ivr`, `Value "${choiceIvr}" already used in a previous response`)
        }
      }
      ivr.push(...choice.responses[context.defaultLanguage].ivr)
    }

    values.push(choice.value)
  }
}

const validateChoice = (path, choice: Choice, context) => {
  if (isBlank(choice.value)) {
    addError(context, `${path}.value`, 'Response must not be blank')
  }

  if (context.sms &&
      choice.responses[context.defaultLanguage] &&
      choice.responses[context.defaultLanguage].sms &&
      choice.responses[context.defaultLanguage].sms.length == 0) {
    addError(context, `${path}.sms`, 'SMS must not be blank')
  }

  if (context.ivr) {
    if (choice.responses[context.defaultLanguage] &&
        choice.responses[context.defaultLanguage].ivr &&
        choice.responses[context.defaultLanguage].ivr.length == 0) {
      addError(context, `${path}.ivr`, '"Phone call" must not be blank')
    }

    if (choice.responses[context.defaultLanguage] &&
        choice.responses[context.defaultLanguage].ivr &&
        choice.responses[context.defaultLanguage].ivr.some(value => !value.match('^[0-9#*]*$'))) {
      addError(context, `${path}.ivr`, '"Phone call" must only consist of single digits, "#" or "*"')
    }
  }
}

const addError = (context, path, error) => {
  context.errors[path] = context.errors[path] || []
  context.errors[path].push(error)
}

const isBlank = (value: string) => {
  return !value || value.trim().length == 0
}

export const stepStoreValues = (questionnaire: Questionnaire) => {
  const multipleChoiceSteps = filter(questionnaire.steps, (step) =>
    step.type == 'multiple-choice'
  )

  return reduce(multipleChoiceSteps, (options, step) => {
    options[step.store] = map(step.choices, (choice) =>
      choice.value
    )
    return options
  }, {})
}

export const csvForTranslation = (questionnaire: Questionnaire) => {
  const defaultLang = questionnaire.defaultLanguage
  const nonDefaultLangs = filter(questionnaire.languages, lang => lang !== defaultLang)

  // First column is the default lang, then the rest of the langs
  const headers = concat([defaultLang], nonDefaultLangs)
  let rows = [headers.map(h => `"${h}"`)]

  // Keep a record of exported strings to avoid dups
  let exported = {}

  questionnaire.steps.forEach(step => {
    if (step.type !== 'language-selection') {
      // Sms Prompt
      if (step.prompt[defaultLang] && step.prompt[defaultLang] && step.prompt[defaultLang].sms && step.prompt[defaultLang].sms.trim().length != 0) {
        const defaultSms = step.prompt[defaultLang].sms
        if (!exported[defaultSms]) {
          exported[defaultSms] = true
          rows.push(headers.map(lang => {
            if (step.prompt[lang] && step.prompt[lang].sms) {
              return `"${step.prompt[lang].sms}"`
            } else {
              return '""'
            }
          }))
        }
      }

      // Ivr Prompt
      if (step.prompt[defaultLang] && step.prompt[defaultLang] && step.prompt[defaultLang].ivr && step.prompt[defaultLang].ivr.text && step.prompt[defaultLang].ivr.text.trim().length != 0) {
        const defaultIvr = step.prompt[defaultLang].ivr.text
        if (!exported[defaultIvr]) {
          exported[defaultIvr] = true
          rows.push(headers.map(lang => {
            if (step.prompt[lang] && step.prompt[lang].ivr) {
              return `"${step.prompt[lang].ivr.text}"`
            } else {
              '""'
            }
          }))
        }
      }

      // Sms Prompt. Note IVR responses shouldn't be translated because it is expected to be a digit.
      if (step.type === 'multiple-choice') {
        step.choices.forEach(choice => {
          // Response sms
          const defaultResponseSms = choice.responses[defaultLang].sms.join(', ')
          if (defaultResponseSms.trim().length != 0 && !exported[defaultResponseSms]) {
            exported[defaultResponseSms] = true
            rows.push(headers.map(lang => {
              if (choice.responses[lang]) {
                return `"${choice.responses[lang].sms.join(', ')}"`
              } else {
                return '""'
              }
            }))
          }
        })
      }
    }
  })

  return rows
}

export default validateReducer(fetchReducer(actions, dataReducer))

const changeNumericRanges = (state, action) => {
  return changeStep(state, action.stepId, step => {
    // validate
    let rangesDelimiters = action.rangesDelimiters
    let minValue = action.minValue ? parseInt(action.minValue) : null
    let maxValue = action.maxValue ? parseInt(action.maxValue) : null
    let values = []
    if (minValue != null) {
      values.push(minValue)
    }
    if (rangesDelimiters) {
      let delimiters = rangesDelimiters.split(',')
      values = values.concat(delimiters.map((e) => { return parseInt(e) }))
    }
    if (maxValue != null) {
      values.push(maxValue)
    }

    let isValid = true
    let i = 0
    while (isValid && i < values.length - 1) {
      isValid = values[i] < values[i + 1]
      i++
    }

    if (!isValid) {
      return {
        ...step,
        minValue: minValue,
        maxValue: maxValue,
        rangesDelimiters: rangesDelimiters
      }
    }

    // generate ranges
    if (minValue == null) {
      values.unshift(null)
    }
    if (maxValue != null) {
      values.pop()
    }

    let ranges = []
    for (let [i, from] of values.entries()) {
      let to = i < (values.length - 1) ? (values[i + 1] - 1) : maxValue
      let prevRange = step.ranges.find((range) => {
        return range.from == from && range.to == to
      })
      if (prevRange) {
        ranges.push({...prevRange})
      } else {
        ranges.push({
          from: from,
          to: to,
          skipLogic: null
        })
      }
    }

    // be happy
    return {
      ...step,
      minValue: minValue,
      maxValue: maxValue,
      rangesDelimiters: rangesDelimiters,
      ranges: ranges
    }
  })
}

const changeRangeSkipLogic = (state, action) => {
  return changeStep(state, action.stepId, step => {
    let newRange = {
      ...step.ranges[action.rangeIndex],
      skipLogic: action.skipLogic
    }
    return {
      ...step,
      ranges: [
        ...step.ranges.slice(0, action.rangeIndex),
        newRange,
        ...step.ranges.slice(action.rangeIndex + 1)
      ]
    }
  })
}
