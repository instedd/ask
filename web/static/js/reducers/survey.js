// @flow
import * as actions from '../actions/survey'
import fetchReducer from './fetch'
import drop from 'lodash/drop'
import flatten from 'lodash/flatten'
import map from 'lodash/map'
import split from 'lodash/split'
import find from 'lodash/find'
import findIndex from 'lodash/findIndex'
import isEqual from 'lodash/isEqual'
import uniqWith from 'lodash/uniqWith'
import every from 'lodash/every'
import some from 'lodash/some'
import without from 'lodash/without'
import filter from 'lodash/filter'

const k = (...args: any) => args

export const dataReducer = (state: Survey, action: any): Survey => {
  switch (action.type) {
    case actions.CHANGE_NAME: return changeName(state, action)
    case actions.CHANGE_IS_PANEL_SURVEY: return changeIsPanelSurvey(state, action)
    case actions.CHANGE_DESCRIPTION: return changeDescription(state, action)
    case actions.CHANGE_CUTOFF: return changeCutoff(state, action)
    case actions.TOGGLE_COUNT_PARTIAL_RESULTS: return toggleCountPartialResults(state, action)
    case actions.CHANGE_QUOTA: return quotaChange(state, action)
    case actions.CHANGE_COMPARISON_RATIO: return comparisonRatioChange(state, action)
    case actions.CHANGE_QUESTIONNAIRE: return changeQuestionnaire(state, action)
    case actions.TOGGLE_DAY: return toggleDay(state, action)
    case actions.SET_SCHEDULE_TO: return setScheduleTo(state, action)
    case actions.SET_SCHEDULE_FROM: return setScheduleFrom(state, action)
    case actions.ADD_SCHEDULE_BLOCKED_DAY: return addScheduleBlockedDay(state, action)
    case actions.REMOVE_SCHEDULE_BLOCKED_DAY: return removeScheduleBlockedDay(state, action)
    case actions.CLEAR_SCHEDULE_BLOCKED_DAYS: return clearScheduleBlockedDays(state, action)
    case actions.SELECT_MODE: return selectMode(state, action)
    case actions.CHANGE_MODE_COMPARISON: return changeModeComparison(state, action)
    case actions.CHANGE_QUESTIONNAIRE_COMPARISON: return changeQuestionnaireComparison(state, action)
    case actions.UPDATE_RESPONDENTS_COUNT: return updateRespondentsCount(state, action)
    case actions.UPDATE_LOCK: return updateLock(state, action)
    case actions.SET_STATE: return setState(state, action)
    case actions.SET_TIMEZONE: return setTimezone(state, action)
    case actions.SET_QUOTA_VARS: return setQuotaVars(state, action)
    case actions.CHANGE_IVR_RETRY_CONFIGURATION: return changeIvrRetryConfiguration(state, action)
    case actions.CHANGE_SMS_RETRY_CONFIGURATION: return changeSmsRetryConfiguration(state, action)
    case actions.CHANGE_MOBILEWEB_RETRY_CONFIGURATION: return changeMobileWebRetryConfiguration(state, action)
    case actions.CHANGE_FALLBACK_DELAY: return changeFallbackDelay(state, action)
    case actions.RECEIVE_LINK: return receiveLink(state, action)
    case actions.REFRESH_LINK: return refreshLink(state, action)
    case actions.DELETE_LINK: return deleteLink(state, action)
    case actions.SAVED: return saved(state, action)
    default: return state
  }
}

const validateReducer = (reducer: StoreReducer<Survey>): StoreReducer<Survey> => {
  return (state: ?DataStore<Survey>, action: any) => {
    const newState = reducer(state, action)
    validate(newState)
    return newState
  }
}

const dirtyPredicate = (action, oldData, newData) => {
  switch (action.type) {
    case actions.RECEIVE_LINK: return false
    case actions.REFRESH_LINK: return false
    case actions.DELETE_LINK: return false
    case actions.CHANGE_NAME: return false
    case actions.CHANGE_DESCRIPTION: return false
    case actions.UPDATE_LOCK: return false
    default: return true
  }
}

export default validateReducer(fetchReducer(actions, dataReducer, null, dirtyPredicate))

const validate = (state) => {
  state.errorsByPath = {}
  validateRetry(state, 'sms', 'smsRetryConfiguration')
  validateRetry(state, 'ivr', 'ivrRetryConfiguration')
  validateRetry(state, 'mobileweb', 'mobilewebRetryConfiguration')
  validateFallbackDelay(state)
}

const validateRetry = (state: DataStore<Survey>, mode, key) => {
  if (!state.data) return

  const data = state.data

  const modes = data.mode
  if (!modes) return

  // Don't validate retry configuration for a mode that's not active (#655)
  if (!some(modes, ms => some(ms, m => m == mode))) return

  const retriesValue = data[key]
  if (!retriesValue) return

  let values = retriesValue.split(' ')
  values = values.filter((v) => v)
  const invalid = values.some((recontactTime) => !isValidReContactTime(recontactTime))
  if (invalid) {
    state.errorsByPath[key] = [k('Re-contact configuration is invalid')]
  }
}

const validateFallbackDelay = (state: DataStore<Survey>) => {
  if (!state.data) return

  const data = state.data

  const modes = data.mode
  if (!modes) return

  // Don't validate fallback delay if there's no fallback mode
  if (!some(modes, ms => ms.length > 1)) return

  const fallbackDelay = data.fallbackDelay
  if (!fallbackDelay) return

  const invalid = !isValidReContactTime(fallbackDelay)
  if (invalid) {
    state.errorsByPath.fallbackDelay = [k('Fallback delay is invalid')]
  }
}

/**
 * Recontacts are at least every 10m
 * So the minimum by:
 *  - Days: 1d
 *  - Hours: 1h
 *  - Minutes: 10m
 */
const isValidReContactTime = (recontactTime) => {
  const matches = recontactTime.match(/^(\d+)([hdm])$/)
  if (matches == null) return false
  const [quantity, unit] = [parseInt(matches[1]), matches[2]]
  if (quantity == 0) return false
  if (unit == 'm' && quantity < 10) return false
  return true
}

const changeName = (state, action) => {
  return {
    ...state,
    name: action.newName
  }
}

const changeIsPanelSurvey = (state, action) => {
  return {
    ...state,
    isPanelSurvey: action.isPanelSurvey
  }
}

const changeDescription = (state, action) => {
  return {
    ...state,
    description: action.newDescription
  }
}

const changeCutoff = (state, action) => {
  return {
    ...state,
    cutoff: action.cutoff
  }
}

const toggleCountPartialResults = (state, action) => {
  return {
    ...state,
    countPartialResults: !state.countPartialResults
  }
}

const setState = (state, action) => {
  return {
    ...state,
    state: action.state
  }
}

const setQuotaVars = (state, action) => {
  const vars = map(action.vars, (storeVar) => storeVar.var)
  const cutoff = vars.length == 0 ? state.cutoff : null
  return {
    ...state,
    quotas: {
      vars,
      buckets: bucketsFor(action.vars, action.options)
    },
    cutoff
  }
}

const bucketsFor = (storeVars, options) => {
  if (storeVars.length == 0) {
    return []
  } else {
    return buildBuckets(storeVars, options)
  }
}

const buildBuckets = (storeVars, options) => {
  const firstVar = options[storeVars[0].var]

  let values = firstVar.values
  if (firstVar.type == 'numeric') {
    values = intervalsFrom(storeVars[0].steps)
  }

  return flatten(map(values, (value) => {
    let buckets = []
    if (drop(storeVars).length == 0) {
      buckets = [{}]
    } else {
      buckets = buildBuckets(drop(storeVars), options)
    }

    return map(buckets, (bucket) => {
      let condition = []
      if (bucket.condition && bucket.condition.length > 0) {
        condition = bucket.condition
      }

      return ({
        ...bucket,
        condition: [
          ...condition,
          {
            store: storeVars[0].var,
            value: value
          }
        ],
        quota: 0
      })
    })
  }))
}

const intervalsFrom = (valueString) => {
  const values = map(split(valueString, ','), (value) => parseInt(value.trim()))
  if (values.length <= 1) {
    return []
  }

  return [[values[0], values[1] - 1], ...intervalsFrom(drop(values))]
}

const comparisonRatioChange = (state, action) => {
  const bucketIndex = findIndex(state.comparisons, (bucket) =>
    bucket.questionnaireId == action.questionnaireId && isEqual(bucket.mode, action.mode)
  )
  return {
    ...state,
    comparisons: [
      ...state.comparisons.slice(0, bucketIndex),
      {
        ...state.comparisons[bucketIndex],
        ratio: action.ratio
      },
      ...state.comparisons.slice(bucketIndex + 1)
    ]
  }
}

const quotaChange = (state, action) => {
  const bucketIndex = getBucketIndexFromCondition(state.quotas.buckets, action.condition)
  return {
    ...state,
    quotas: {
      ...state.quotas,
      buckets: [
        ...state.quotas.buckets.slice(0, bucketIndex),
        {
          ...state.quotas.buckets[bucketIndex],
          quota: action.quota
        },
        ...state.quotas.buckets.slice(bucketIndex + 1)
      ]
    }
  }
}

const getBucketIndexFromCondition = (buckets: Bucket[], condition: Condition) => {
  return findIndex(buckets, (bucket) =>
    isEqual(bucket.condition, condition)
  )
}

export const getQuotasTotal = (quotaBuckets: Bucket[]) => {
  if (quotaBuckets) {
    let quotasSum = quotaBuckets.reduce(function(sum, current) {
      return sum + parseInt(current.quota)
    }, 0)
    return quotasSum
  }
}

export const sumQuotasIfValid = (condition: Condition[], buckets: Bucket[], newQuota: number) => {
  let quotasSum = getQuotasTotal(buckets.filter((bucket) => !isEqual(bucket.condition, condition)))
  quotasSum += parseInt(newQuota)
  return quotasSum
}

export const rebuildInputFromQuotaBuckets = (store: string, survey: Survey) => {
  const buckets = survey.quotas.buckets.filter((bucket) => bucket.condition.map((condition) => condition.store).includes(store))
  let conditions = uniqWith(buckets.map((bucket) => find(bucket.condition, (condition) => condition.store == store).value), isEqual)
  conditions = conditions.map(x => [x[0], x[1] + 1])
  conditions = flatten(conditions)
  conditions = uniqWith(conditions, isEqual)
  return conditions.join()
}

const saved = (state, action) => {
  return {
    ...state,
    state: action.data.state
  }
}

const changeQuestionnaire = (state, action) => {
  let questionnaireId = parseInt(action.questionnaire)

  let newQuestionnaireIds
  let questionnaireIds = state.questionnaireIds || []
  let questionnaireComparison = questionnaireIds.length > 1 || state.questionnaireComparison

  if (questionnaireComparison) {
    newQuestionnaireIds = questionnaireIds.slice()
    let index = questionnaireIds.indexOf(questionnaireId)
    if (index == -1) {
      newQuestionnaireIds.push(questionnaireId)
    } else {
      newQuestionnaireIds.splice(index, 1)
    }
  } else {
    newQuestionnaireIds = [questionnaireId]
  }

  // If any questionnaire has a mode that's not present in the current survey mode,
  // unleselect the mode
  let mode = state.mode
  if (mode && mode.length > 0 && action.questionnaires && !questionnairesMatchModes(mode, newQuestionnaireIds, action.questionnaires)) {
    mode = []
  }

  return {
    ...state,
    questionnaireIds: newQuestionnaireIds,
    questionnaireComparison,
    mode,
    comparisons: buildComparisons(state.modeComparison, questionnaireComparison, state.mode, newQuestionnaireIds),
    quotas: {
      vars: [],
      buckets: []
    }
  }
}

const questionnairesMatchModes = (modes, ids, questionnaires) => {
  return every(modes, mode =>
    every(mode, m =>
      ids && every(ids, id =>
        questionnaires[id] && questionnaires[id].modes && questionnaires[id].modes.indexOf(m) != -1)))
}

const toggleDay = (state, action) => {
  return {
    ...state,
    schedule: {
      ...state.schedule,
      dayOfWeek: {
        ...state.schedule.dayOfWeek,
        [action.day]: !state.schedule.dayOfWeek[action.day]
      }
    }
  }
}

const setScheduleFrom = (state, action) => {
  let endTime = state.schedule.endTime
  if (action.hour >= endTime) {
    endTime = action.nextHour
  }
  return {
    ...state,
    schedule: {
      ...state.schedule,
      endTime: endTime,
      startTime: action.hour
    }
  }
}

const setScheduleTo = (state, action) => {
  let startTime = state.schedule.startTime
  if (action.hour <= startTime) {
    startTime = action.previousHour
  }
  return {
    ...state,
    schedule: {
      ...state.schedule,
      startTime: startTime,
      endTime: action.hour
    }
  }
}

const addScheduleBlockedDay = (state, action) => {
  return {
    ...state,
    schedule: {
      ...state.schedule,
      blockedDays: Array.from(new Set([
        ...state.schedule.blockedDays,
        action.day
      ]))
    }
  }
}

const removeScheduleBlockedDay = (state, action) => {
  return {
    ...state,
    schedule: {
      ...state.schedule,
      blockedDays: without(state.schedule.blockedDays, action.day)
    }
  }
}

const clearScheduleBlockedDays = (state, action) => {
  return {
    ...state,
    schedule: {
      ...state.schedule,
      blockedDays: []
    }
  }
}

const selectMode = (state, action) => {
  let newMode
  let stateMode = state.mode || []
  let modeComparison = stateMode.length > 1 || state.modeComparison

  if (isEqual(action.mode, state.mode)) {
    return state
  }

  if (modeComparison) {
    let mode = state.mode || []
    if (some(mode, m => isEqual(m, action.mode))) {
      newMode = mode.filter(m => !isEqual(m, action.mode))
    } else {
      newMode = mode.slice()
      newMode.push(action.mode)
    }
  } else {
    if (action.mode.length > 0) {
      newMode = [action.mode]
    } else {
      newMode = []
    }
  }

  return {
    ...state,
    mode: newMode,
    modeComparison,
    comparisons: buildComparisons(modeComparison, state.questionnaireComparison, newMode, state.questionnaireIds)
  }
}

const changeModeComparison = (state, action) => {
  let newMode = state.mode || []
  let modeComparison = newMode.length > 1 || state.modeComparison
  let newModeComparison = !modeComparison

  if (!newModeComparison) {
    if (newMode.length == 1) {
      newMode = [newMode[0]]
    } else {
      newMode = []
    }
  }

  return {
    ...state,
    mode: newMode,
    comparisons: buildComparisons(newModeComparison, state.questionnaireComparison, newMode, state.questionnaireIds),
    modeComparison: newModeComparison
  }
}

const changeQuestionnaireComparison = (state, action) => {
  let newQuestionnaireIds = state.questionnaireIds || []
  let questionnaireComparison = newQuestionnaireIds.length > 1 || state.questionnaireComparison
  let newQuestionnaireComparison = !questionnaireComparison

  if (!newQuestionnaireComparison) {
    if (newQuestionnaireIds.length == 1) {
      newQuestionnaireIds = [newQuestionnaireIds[0]]
    } else {
      newQuestionnaireIds = []
    }
  }

  return {
    ...state,
    questionnaireIds: newQuestionnaireIds,
    questionnaireComparison: newQuestionnaireComparison,
    comparisons: buildComparisons(state.modeComparison, newQuestionnaireComparison, state.mode, newQuestionnaireIds)
  }
}

const buildComparisons = (modeComparison, questionnaireComparison, modes, questionnaires) => {
  if ((modeComparison || questionnaireComparison) && modes && questionnaires) {
    return flatten(map(modes, (mode) => {
      return map(questionnaires, (questionnaire) => {
        return ({
          mode: mode,
          questionnaireId: questionnaire
        })
      })
    }))
  } else {
    return []
  }
}

const setTimezone = (state, action) => {
  return {
    ...state,
    schedule: {
      ...state.schedule,
      timezone: action.timezone
    }
  }
}

const updateRespondentsCount = (state, action) => {
  return {
    ...state,
    respondentsCount: action.respondentsCount
  }
}

const updateLock = (state, action) => {
  return {
    ...state,
    locked: action.newLockValue
  }
}

const changeSmsRetryConfiguration = (state, action) => {
  return {
    ...state,
    smsRetryConfiguration: action.smsRetryConfiguration
  }
}

const changeIvrRetryConfiguration = (state, action) => {
  return {
    ...state,
    ivrRetryConfiguration: action.ivrRetryConfiguration
  }
}

const changeMobileWebRetryConfiguration = (state, action) => {
  return {
    ...state,
    mobilewebRetryConfiguration: action.mobilewebRetryConfiguration
  }
}
const changeFallbackDelay = (state, action) => {
  return {
    ...state,
    fallbackDelay: action.fallbackDelay
  }
}

const receiveLink = (state, action) => {
  return {
    ...state,
    links: [
      ...state.links,
      action.link
    ]
  }
}

const refreshLink = (state, action) => {
  return {
    ...state,
    links: [
      ...filter(state.links, (link) => link.name != action.link.name),
      action.link
    ]
  }
}

const deleteLink = (state, action) => {
  return {
    ...state,
    links: without(state.links, action.link)
  }
}
