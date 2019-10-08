/* eslint-env mocha */
// @flow
import expect from 'expect'
import assert from 'assert'
import { playActionsFromState } from '../spec_helper'
import reducer, {rebuildInputFromQuotaBuckets} from '../../../web/static/js/reducers/survey'
import { modeLabel } from '../../../web/static/js/questionnaire.mode'
import * as actions from '../../../web/static/js/actions/survey'
import * as questionnaireActions from '../../../web/static/js/actions/questionnaire'
import deepFreeze from '../../../web/static/vendor/js/deepFreeze'
import { survey } from '../fixtures'

describe('survey reducer', () => {
  const initialState = reducer(undefined, {})

  const playActions = playActionsFromState(initialState, reducer)

  it('has a sane initial state', () => {
    expect(initialState.fetching).toEqual(false)
    expect(initialState.filter).toEqual(null)
    expect(initialState.data).toEqual(null)
    expect(initialState.dirty).toEqual(false)
    expect(initialState.saving).toEqual(false)
  })

  it('should fetch', () => {
    assert(!actions.shouldFetch({...initialState, fetching: true, filter: {projectId: 1, id: 1}}, 1, 1))
    assert(actions.shouldFetch({...initialState, fetching: true, filter: null}, 1, 1))
    assert(actions.shouldFetch({...initialState, fetching: true, filter: {projectId: 1, id: 1}}, 2, 2))
    assert(actions.shouldFetch({...initialState, fetching: false, filter: null}, 1, 1))
    assert(actions.shouldFetch({...initialState, fetching: false, filter: {projectId: 1, id: 1}}, 1, 1))
  })

  it('fetches a survey', () => {
    const state = playActions([
      actions.fetch(1, 1)
    ])

    expect(state).toEqual({
      ...state,
      fetching: true,
      filter: {
        projectId: 1,
        id: 1
      },
      data: null
    })
  })

  it('receives a survey', () => {
    const state = playActions([
      actions.fetch(1, 1),
      actions.receive(survey)
    ])
    expect(state.fetching).toEqual(false)
    expect(state.data).toEqual(survey)
  })

  it('receiving a survey without an initial fetch should discard the survey', () => {
    const state = playActions([
      actions.receive(survey)
    ])
    expect(state.fetching).toEqual(false)
    expect(state.filter).toEqual(null)
    expect(state.data).toEqual(null)
  })

  it('clears data when fetching a different survey', () => {
    const state = playActions([
      actions.fetch(1, 1),
      actions.receive(survey),
      actions.fetch(2, 2)
    ])

    expect(state).toEqual({
      ...state,
      fetching: true,
      filter: {
        projectId: 2,
        id: 2
      },
      data: null
    })
  })

  it('keeps old data when fetching new data for the same filter', () => {
    const state = playActions([
      actions.fetch(1, 1),
      actions.receive(survey),
      actions.fetch(1, 1)
    ])

    expect(state).toEqual({
      ...state,
      fetching: true,
      data: survey
    })
  })

  it('ignores data received based on different filter', () => {
    const state = playActions([
      actions.fetch(2, 2),
      actions.receive(survey)
    ])

    expect(state).toEqual({
      ...state,
      filter: {projectId: 2, id: 2},
      fetching: true,
      data: null
    })
  })

  it('should be marked as dirty if something changed', () => {
    const state = playActions([
      actions.fetch(1, 1),
      actions.receive(survey),
      actions.toggleDay('wed')
    ])

    expect(state).toEqual({
      ...state,
      dirty: true
    })
  })

  it('should be marked saving when saving', () => {
    const state = playActions([
      actions.fetch(1, 1),
      actions.receive(survey),
      actions.toggleDay('wed'),
      actions.saving()
    ])

    expect(state).toEqual({
      ...state,
      dirty: false,
      saving: true
    })
  })

  it('should be marked clean and saved when saved', () => {
    const state = playActions([
      actions.fetch(1, 1),
      actions.receive(survey),
      actions.toggleDay('wed'),
      actions.saving(),
      actions.saved(survey)
    ])

    expect(state).toEqual({
      ...state,
      saving: false,
      dirty: false
    })
    expect(state.data.schedule.dayOfWeek)
    .toEqual({'sun': true, 'mon': true, 'tue': true, 'wed': false, 'thu': true, 'fri': true, 'sat': true})
  })

  it('should update state when saved', () => {
    const state = playActions([
      actions.fetch(1, 1),
      actions.receive(survey),
      actions.toggleDay('wed'),
      actions.saving(),
      actions.saved({...survey, state: 'foo'})
    ])

    expect(state.data.state).toEqual('foo')
  })

  it('should be marked dirty if there were a change in the middle', () => {
    const state = playActions([
      actions.fetch(1, 1),
      actions.receive(survey),
      actions.toggleDay('wed'),
      actions.saving(),
      actions.toggleDay('wed'),
      actions.saved(survey)
    ])

    expect(state).toEqual({
      ...state,
      saving: false,
      dirty: true
    })
    expect(state.data).toEqual(survey)
  })

  it('shouldn\'t be marked as dirty if something changed in a different reducer', () => {
    const state = playActions([
      actions.fetch(1, 1),
      actions.receive(survey),
      questionnaireActions.changeName('foo')
    ])
    expect(state).toEqual({
      ...state,
      dirty: false
    })
  })

  it('should toggle a single day preserving the others', () => {
    const state = playActions([
      actions.fetch(1, 1),
      actions.receive(survey),
      actions.toggleDay('wed')
    ])
    expect(state.data.schedule.dayOfWeek)
    .toEqual({'sun': true, 'mon': true, 'tue': true, 'wed': false, 'thu': true, 'fri': true, 'sat': true})
  })

  it('should set timezone', () => {
    const result = playActions([
      actions.fetch(1, 1),
      actions.receive(survey),
      actions.setTimezone('America/Cayenne')
    ])
    expect(result.data.schedule.timezone).toEqual('America/Cayenne')
  })

  it('should change sms retry configuration property', () => {
    const state = playActions([
      actions.fetch(1, 1),
      actions.receive(survey),
      actions.changeSmsRetryConfiguration('15h 1d')
    ])
    expect(state.data.smsRetryConfiguration).toEqual('15h 1d')
  })

  it('should change ivr retry configuration property', () => {
    const state = playActions([
      actions.fetch(1, 1),
      actions.receive(survey),
      actions.changeIvrRetryConfiguration('15h 1d')
    ])
    expect(state.data.ivrRetryConfiguration).toEqual('15h 1d')
  })

  it('should not add sms retry attempts errors if configuration is invalid', () => {
    const state = playActions([
      actions.fetch(1, 1),
      actions.receive(survey),
      actions.changeSmsRetryConfiguration('12j')
    ])
    expect(state.errorsByPath.smsRetryConfiguration).toEqual('Re-contact configuration is invalid')
  })

  it('should not add ivr retry attempts errors if configuration is invalid', () => {
    const state = playActions([
      actions.fetch(1, 1),
      actions.receive(survey),
      actions.selectMode(['ivr']),
      actions.changeIvrRetryConfiguration('12j')
    ])
    expect(state.errorsByPath.ivrRetryConfiguration).toEqual('Re-contact configuration is invalid')
  })

  it('should validate fallback delay', () => {
    const state = playActions([
      actions.fetch(1, 1),
      actions.receive(survey),
      actions.selectMode(['sms', 'ivr']),
      actions.changeFallbackDelay('12j')
    ])
    expect(state.errorsByPath.fallbackDelay).toEqual('Fallback delay is invalid')
  })

  it('should not validate fallback delay if only one mode is selected', () => {
    const state = playActions([
      actions.fetch(1, 1),
      actions.receive(survey),
      actions.changeFallbackDelay('12j')
    ])
    expect(state.errors.fallbackDelay).toEqual(null)
  })

  it('should not add retries errors if both sms and ivr configurations are valid', () => {
    const state = playActions([
      actions.fetch(1, 1),
      actions.receive(survey),
      actions.changeIvrRetryConfiguration('2h 5d'),
      actions.changeIvrRetryConfiguration('3m 1h')
    ])
    expect(!state.errors.smsRetryConfiguration)
    expect(!state.errors.ivrRetryConfiguration)
  })

  it('should set quota vars and define the buckets for the new vars', () => {
    const questionnaire = deepFreeze({
      steps: [
        {
          type: 'multiple-choice',
          store: 'Smokes',
          choices: [{value: 'Yes'}, {value: 'No'}]
        },
        {
          type: 'multiple-choice',
          store: 'Gender',
          choices: [{value: 'Male'}, {value: 'Female'}]
        },
        {
          type: 'multiple-choice',
          store: 'Exercises',
          choices: [{value: 'Yes'}, {value: 'No'}]
        }
      ],
      id: 1
    })
    const state = playActions([
      actions.fetch(1, 1),
      actions.receive(survey),
      actions.setQuotaVars([{var: 'Smokes'}, {var: 'Gender'}, {var: 'Exercises'}], questionnaire)
    ])

    expect(state).toEqual({
      ...state,
      data: {
        ...state.data,
        quotas: {
          vars: ['Smokes', 'Gender', 'Exercises'],
          buckets: [
            {'condition': [{store: 'Exercises', value: 'Yes'}, {store: 'Gender', value: 'Male'}, {store: 'Smokes', value: 'Yes'}], 'quota': 0},
            {'condition': [{store: 'Exercises', value: 'No'}, {store: 'Gender', value: 'Male'}, {store: 'Smokes', value: 'Yes'}], 'quota': 0},
            {'condition': [{store: 'Exercises', value: 'Yes'}, {store: 'Gender', value: 'Female'}, {store: 'Smokes', value: 'Yes'}], 'quota': 0},
            {'condition': [{store: 'Exercises', value: 'No'}, {store: 'Gender', value: 'Female'}, {store: 'Smokes', value: 'Yes'}], 'quota': 0},
            {'condition': [{store: 'Exercises', value: 'Yes'}, {store: 'Gender', value: 'Male'}, {store: 'Smokes', value: 'No'}], 'quota': 0},
            {'condition': [{store: 'Exercises', value: 'No'}, {store: 'Gender', value: 'Male'}, {store: 'Smokes', value: 'No'}], 'quota': 0},
            {'condition': [{store: 'Exercises', value: 'Yes'}, {store: 'Gender', value: 'Female'}, {store: 'Smokes', value: 'No'}], 'quota': 0},
            {'condition': [{store: 'Exercises', value: 'No'}, {store: 'Gender', value: 'Female'}, {store: 'Smokes', value: 'No'}], 'quota': 0}
          ]
        }
      }
    })
  })

  it('should build a bucket for one var', () => {
    const questionnaire = deepFreeze({
      steps: [
        {
          type: 'multiple-choice',
          store: 'Smokes',
          choices: [{value: 'Yes'}, {value: 'No'}]
        },
        {
          type: 'multiple-choice',
          store: 'Gender',
          choices: [{value: 'Male'}, {value: 'Female'}]
        },
        {
          type: 'multiple-choice',
          store: 'Exercises',
          choices: [{value: 'Yes'}, {value: 'No'}]
        }
      ],
      id: 1
    })
    const state = playActions([
      actions.fetch(1, 1),
      actions.receive(survey),
      actions.setQuotaVars([{var: 'Smokes'}], questionnaire)
    ])

    expect(state).toEqual({
      ...state,
      data: {
        ...state.data,
        quotas: {
          vars: ['Smokes'],
          buckets: [
            {'condition': [{store: 'Smokes', value: 'Yes'}], 'quota': 0},
            {'condition': [{store: 'Smokes', value: 'No'}], 'quota': 0}
          ]
        }
      }
    })
  })

  it('should clear the bucket list when there is no var selected', () => {
    const questionnaire = deepFreeze({
      steps: [
        {
          type: 'multiple-choice',
          store: 'Smokes',
          choices: [{value: 'Yes'}, {value: 'No'}]
        },
        {
          type: 'multiple-choice',
          store: 'Gender',
          choices: [{value: 'Male'}, {value: 'Female'}]
        },
        {
          type: 'multiple-choice',
          store: 'Exercises',
          choices: [{value: 'Yes'}, {value: 'No'}]
        }
      ],
      id: 1
    })
    const state = playActions([
      actions.fetch(1, 1),
      actions.receive(survey),
      actions.setQuotaVars([{var: 'Smokes'}, {var: 'Gender'}, {var: 'Exercises'}], questionnaire),
      actions.setQuotaVars([], questionnaire)
    ])

    expect(state).toEqual({
      ...state,
      data: {
        ...state.data,
        quotas: {
          vars: [],
          buckets: []
        }
      }
    })
  })

  it('should change quota for a given condition', () => {
    const questionnaire = deepFreeze({
      steps: [
        {
          type: 'multiple-choice',
          store: 'Smokes',
          choices: [{value: 'Yes'}, {value: 'No'}]
        },
        {
          type: 'multiple-choice',
          store: 'Gender',
          choices: [{value: 'Male'}, {value: 'Female'}]
        },
        {
          type: 'multiple-choice',
          store: 'Exercises',
          choices: [{value: 'Yes'}, {value: 'No'}]
        }
      ],
      id: 1
    })
    const state = playActions([
      actions.fetch(1, 1),
      actions.receive(survey),
      actions.setQuotaVars([{var: 'Smokes'}, {var: 'Gender'}, {var: 'Exercises'}], questionnaire),
      actions.quotaChange([{store: 'Exercises', value: 'Yes'}, {store: 'Gender', value: 'Female'}, {store: 'Smokes', value: 'Yes'}], 12345)
    ])

    expect(state).toEqual({
      ...state,
      data: {
        ...state.data,
        quotas: {
          vars: ['Smokes', 'Gender', 'Exercises'],
          buckets: [
            {'condition': [{store: 'Exercises', value: 'Yes'}, {store: 'Gender', value: 'Male'}, {store: 'Smokes', value: 'Yes'}], 'quota': 0},
            {'condition': [{store: 'Exercises', value: 'No'}, {store: 'Gender', value: 'Male'}, {store: 'Smokes', value: 'Yes'}], 'quota': 0},
            {'condition': [{store: 'Exercises', value: 'Yes'}, {store: 'Gender', value: 'Female'}, {store: 'Smokes', value: 'Yes'}], 'quota': 12345},
            {'condition': [{store: 'Exercises', value: 'No'}, {store: 'Gender', value: 'Female'}, {store: 'Smokes', value: 'Yes'}], 'quota': 0},
            {'condition': [{store: 'Exercises', value: 'Yes'}, {store: 'Gender', value: 'Male'}, {store: 'Smokes', value: 'No'}], 'quota': 0},
            {'condition': [{store: 'Exercises', value: 'No'}, {store: 'Gender', value: 'Male'}, {store: 'Smokes', value: 'No'}], 'quota': 0},
            {'condition': [{store: 'Exercises', value: 'Yes'}, {store: 'Gender', value: 'Female'}, {store: 'Smokes', value: 'No'}], 'quota': 0},
            {'condition': [{store: 'Exercises', value: 'No'}, {store: 'Gender', value: 'Female'}, {store: 'Smokes', value: 'No'}], 'quota': 0}
          ]
        }
      }
    })
  })

  it('should clear the bucket list when changing the selected questionnaire', () => {
    const questionnaire = deepFreeze({
      steps: [
        {
          type: 'multiple-choice',
          store: 'Smokes',
          choices: [{value: 'Yes'}, {value: 'No'}]
        },
        {
          type: 'multiple-choice',
          store: 'Gender',
          choices: [{value: 'Male'}, {value: 'Female'}]
        },
        {
          type: 'multiple-choice',
          store: 'Exercises',
          choices: [{value: 'Yes'}, {value: 'No'}]
        }
      ],
      id: 1
    })
    const state = playActions([
      actions.fetch(1, 1),
      actions.receive(survey),
      actions.setQuotaVars([{var: 'Smokes'}, {var: 'Gender'}, {var: 'Exercises'}], questionnaire),
      actions.changeQuestionnaire(2)
    ])

    expect(state).toEqual({
      ...state,
      data: {
        ...state.data,
        quotas: {
          vars: [],
          buckets: []
        }
      }
    })
  })

  it('should set quota vars for numeric steps', () => {
    const questionnaire = deepFreeze({
      steps: [
        {
          type: 'multiple-choice',
          store: 'Smokes',
          choices: [{value: 'Yes'}, {value: 'No'}]
        },
        {
          type: 'numeric',
          store: 'Age'
        }
      ],
      id: 1
    })
    const state = playActions([
      actions.fetch(1, 1),
      actions.receive(survey),
      actions.setQuotaVars([{var: 'Smokes', steps: ''}, {var: 'Age', steps: '20, 30, 40, 50, 120'}], questionnaire)
    ])

    expect(state).toEqual({
      ...state,
      data: {
        ...state.data,
        quotas: {
          vars: ['Smokes', 'Age'],
          buckets: [
            {'condition': [{store: 'Age', value: [20, 29]}, {store: 'Smokes', value: 'Yes'}], 'quota': 0},
            {'condition': [{store: 'Age', value: [30, 39]}, {store: 'Smokes', value: 'Yes'}], 'quota': 0},
            {'condition': [{store: 'Age', value: [40, 49]}, {store: 'Smokes', value: 'Yes'}], 'quota': 0},
            {'condition': [{store: 'Age', value: [50, 120]}, {store: 'Smokes', value: 'Yes'}], 'quota': 0},
            {'condition': [{store: 'Age', value: [20, 29]}, {store: 'Smokes', value: 'No'}], 'quota': 0},
            {'condition': [{store: 'Age', value: [30, 39]}, {store: 'Smokes', value: 'No'}], 'quota': 0},
            {'condition': [{store: 'Age', value: [40, 49]}, {store: 'Smokes', value: 'No'}], 'quota': 0},
            {'condition': [{store: 'Age', value: [50, 120]}, {store: 'Smokes', value: 'No'}], 'quota': 0}
          ]
        }
      }
    })
  })

  describe('quota buckets intervals', () => {
    const questionnaire = deepFreeze({
      steps: [
        {
          type: 'numeric',
          store: 'Age'
        }
      ],
      id: 1
    })

    const baseState = deepFreeze(playActions([
      actions.fetch(1, 1),
      actions.receive(survey),
      actions.setQuotaVars([{var: 'Age', steps: '20, 30, 40'}], questionnaire)
    ]))

    let intervalStrings = [
      '20, 30, 40',
      '20, 40, 30',
      '30, 20, 40',
      '30, 40, 20',
      '40, 20, 30',
      '40, 30, 20',
    ]

    intervalStrings.forEach((intervalString) => {
      it('should build sort-insensitive quota buckets intervals', () => {
        const actionsToPlay = [
          actions.fetch(1, 1),
          actions.receive(survey),
          actions.setQuotaVars([{var: 'Age', steps: intervalString}], questionnaire)
        ]
        expect(playActions(actionsToPlay)).toEqual(baseState)
      })
    })
  })

  it('should rebuild input from quota buckets', () => {
    const survey = deepFreeze({
      quotas: {
        vars: ['age'],
        buckets: [
          {
            'condition': [
              { store: 'age', value: [1, 9] }
            ]
          },
          {
            'condition': [
              { store: 'age', value: [10, 50] }
            ]
          }
        ]
      }
    })
    expect(rebuildInputFromQuotaBuckets('age', survey)).toEqual('1,10,50')
  })

  it('changes modeComparison', () => {
    const state = playActions([
      actions.fetch(1, 1),
      actions.receive(survey),
      actions.changeModeComparison()
    ])
    expect(state.data.modeComparison).toEqual(true)

    const state2 = playActionsFromState(state, reducer)([
      actions.changeModeComparison()
    ])
    expect(state2.data.modeComparison).toEqual(false)
  })

  it('selects mode, no comparison', () => {
    const state = playActions([
      actions.fetch(1, 1),
      actions.receive(survey),
      actions.selectMode(['ivr'])
    ])
    expect(state.data.mode).toEqual([['ivr']])
  })

  it('selects empty mode, no comparison', () => {
    const state = playActions([
      actions.fetch(1, 1),
      actions.receive(survey),
      actions.selectMode(['ivr']),
      actions.selectMode([])
    ])
    expect(state.data.mode).toEqual([])
  })

  it('selects mode, comparison', () => {
    const state = playActions([
      actions.fetch(1, 1),
      actions.receive(survey),
      actions.changeModeComparison(),
      actions.selectMode(['ivr'])
    ])
    expect(state.data.mode).toEqual([['sms'], ['ivr']])

    const state2 = playActionsFromState(state, reducer)([
      actions.selectMode(['sms'])
    ])
    expect(state2.data.mode).toEqual([['ivr']])
  })

  it('changes modeComparison with many modes', () => {
    const state = playActions([
      actions.fetch(1, 1),
      actions.receive(survey),
      actions.changeModeComparison(),
      actions.selectMode(['ivr']),
      actions.changeModeComparison()
    ])
    expect(state.data.mode).toEqual([])
  })

  it('changes questionnaireComparison', () => {
    const state = playActions([
      actions.fetch(1, 1),
      actions.receive(survey),
      actions.changeQuestionnaireComparison()
    ])
    expect(state.data.questionnaireComparison).toEqual(true)

    const state2 = playActionsFromState(state, reducer)([
      actions.changeQuestionnaireComparison()
    ])
    expect(state2.data.questionnaireComparison).toEqual(false)
  })

  it('changes questionnaire, no comparison', () => {
    const state = playActions([
      actions.fetch(1, 1),
      actions.receive(survey),
      actions.changeQuestionnaire(2)
    ])
    expect(state.data.questionnaireIds).toEqual([2])
  })

  it('changes questionnaire, with comparison', () => {
    const state = playActions([
      actions.fetch(1, 1),
      actions.receive(survey),
      actions.changeQuestionnaireComparison(),
      actions.changeQuestionnaire(2)
    ])
    expect(state.data.questionnaireIds).toEqual([1, 2])

    const state2 = playActionsFromState(state, reducer)([
      actions.changeQuestionnaire(3)
    ])
    expect(state2.data.questionnaireIds).toEqual([1, 2, 3])

    const state3 = playActionsFromState(state2, reducer)([
      actions.changeQuestionnaire(2)
    ])
    expect(state3.data.questionnaireIds).toEqual([1, 3])
  })

  it('changes questionnaire, resets mode', () => {
    const state = playActions([
      actions.fetch(1, 1),
      actions.receive(survey),
      actions.changeQuestionnaire(2, {'2': {'modes': ['ivr']}})
    ])
    expect(state.data.mode).toEqual([])
  })

  it('changes questionnaireComparison with many questionnaires', () => {
    const state = playActions([
      actions.fetch(1, 1),
      actions.receive(survey),
      actions.changeQuestionnaireComparison(),
      actions.changeQuestionnaire(2),
      actions.changeQuestionnaireComparison()
    ])
    expect(state.data.questionnaireIds).toEqual([])
  })

  it('should generate comparisons when questionnaire comparison is enabled', () => {
    const state = playActions([
      actions.fetch(1, 1),
      actions.receive(survey),
      actions.changeQuestionnaireComparison()
    ])
    expect(state.data.questionnaireIds).toEqual([1])
    expect(state.data.comparisons).toEqual([{'questionnaireId': 1, 'mode': ['sms']}])
  })

  it('should clear comparisons when questionnaire comparisons is disabled', () => {
    const state = playActions([
      actions.fetch(1, 1),
      actions.receive(survey),
      actions.changeQuestionnaireComparison(),
      actions.changeQuestionnaireComparison()
    ])
    expect(state.data.questionnaireIds).toEqual([1])
    expect(state.data.comparisons).toEqual([])
  })

  it('should regenerate comparisons when changing questionnaire with comparison enabled', () => {
    const state = playActions([
      actions.fetch(1, 1),
      actions.receive(survey),
      actions.changeQuestionnaireComparison(),
      actions.changeQuestionnaire(2)
    ])
    expect(state.data.questionnaireIds).toEqual([1, 2])
    expect(state.data.comparisons).toEqual([{'questionnaireId': 1, 'mode': ['sms']}, {'questionnaireId': 2, 'mode': ['sms']}])
  })

  it('should clear comparisons if no questionnaire is selected and questionnaireComparison is enabled', () => {
    const state = playActions([
      actions.fetch(1, 1),
      actions.receive(survey),
      actions.changeQuestionnaireComparison(),
      actions.changeQuestionnaire(1)
    ])
    expect(state.data.questionnaireIds).toEqual([])
    expect(state.data.comparisons).toEqual([])
  })

  it('should generate comparisons when mode comparison is enabled', () => {
    const state = playActions([
      actions.fetch(1, 1),
      actions.receive(survey),
      actions.changeModeComparison()
    ])
    expect(state.data.mode).toEqual([['sms']])
    expect(state.data.comparisons).toEqual([{'mode': ['sms'], 'questionnaireId': 1}])
  })

  it('should clear comparisons when modeComparison is disabled', () => {
    const state = playActions([
      actions.fetch(1, 1),
      actions.receive(survey),
      actions.changeModeComparison(),
      actions.changeModeComparison()
    ])
    expect(state.data.mode).toEqual([['sms']])
    expect(state.data.comparisons).toEqual([])
  })

  it('shouldn\'t clear comparisons when modeComparison is disabled if questionnaireComparison is still enabled', () => {
    const state = playActions([
      actions.fetch(1, 1),
      actions.receive(survey),
      actions.changeQuestionnaireComparison(),
      actions.changeQuestionnaire(2),
      actions.changeModeComparison(),
      actions.changeModeComparison()
    ])
    expect(state.data.mode).toEqual([['sms']])
    expect(state.data.comparisons).toEqual([{'mode': ['sms'], 'questionnaireId': 1}, {'mode': ['sms'], 'questionnaireId': 2}])
  })

  it('shouldn\'t clear comparisons when questionnaireComparison is disabled if modeComparison is still enabled', () => {
    const state = playActions([
      actions.fetch(1, 1),
      actions.receive(survey),
      actions.changeModeComparison(),
      actions.selectMode(['ivr']),
      actions.changeQuestionnaireComparison(),
      actions.changeQuestionnaireComparison()
    ])
    expect(state.data.mode).toEqual([['sms'], ['ivr']])
    expect(state.data.comparisons).toEqual([{'mode': ['sms'], 'questionnaireId': 1}, {'mode': ['ivr'], 'questionnaireId': 1}])
  })

  it('should regenerate comparisons when changing mode with modeComparison enabled', () => {
    const state = playActions([
      actions.fetch(1, 1),
      actions.receive(survey),
      actions.changeModeComparison(),
      actions.selectMode(['ivr'])
    ])
    expect(state.data.mode).toEqual([['sms'], ['ivr']])
    expect(state.data.comparisons).toEqual([{'mode': ['sms'], 'questionnaireId': 1}, {'mode': ['ivr'], 'questionnaireId': 1}])
  })

  it('should clear comparisons when selecting no questionnaire and no mode with mode comparisons enabled', () => {
    const state = playActions([
      actions.fetch(1, 1),
      actions.receive(survey),
      actions.changeQuestionnaireComparison(),
      actions.changeQuestionnaire(1),
      actions.changeQuestionnaireComparison(),
      actions.changeModeComparison(),
      actions.selectMode(['sms'])
    ])
    expect(state.data.mode).toEqual([])
    expect(state.data.comparisons).toEqual([])
  })

  it('should change comparison ratio for a given questionnaire and mode', () => {
    const state = playActions([
      actions.fetch(1, 1),
      actions.receive(survey),
      actions.changeQuestionnaireComparison(),
      actions.changeQuestionnaire(2),
      actions.changeModeComparison(),
      actions.selectMode(['ivr']),
      actions.comparisonRatioChange(2, ['sms'], 0.4)
    ])

    expect(state).toEqual({
      ...state,
      data: {
        ...state.data,
        comparisons: [
          {
            'mode': ['sms'],
            'questionnaireId': 1
          },
          {
            'mode': ['sms'],
            'questionnaireId': 2,
            'ratio': 0.4
          },
          {
            'mode': ['ivr'],
            'questionnaireId': 1
          },
          {
            'mode': ['ivr'],
            'questionnaireId': 2
          }
        ]
      }
    })
  })

  it('should provide proper labels for survey modes', () => {
    expect(modeLabel(['sms'])).toEqual('SMS')
    expect(modeLabel(['ivr'])).toEqual('Phone call')
    expect(modeLabel(['ivr', 'sms'])).toEqual('Phone call with SMS fallback')
    expect(modeLabel(['sms', 'ivr'])).toEqual('SMS with phone call fallback')
  })

  it('should toggle count partial results', () => {
    const state = playActions([
      actions.fetch(1, 1),
      actions.receive(survey),
      actions.toggleCountPartialResults()
    ])
    expect(state.data.countPartialResults).toEqual(true)

    const state2 = playActionsFromState(state, reducer)([
      actions.toggleCountPartialResults()
    ])
    expect(state2.data.countPartialResults).toEqual(false)
  })

  it('should change description', () => {
    const result = playActions([
      actions.fetch(1, 1),
      actions.receive(survey),
      actions.descriptionChanged('initial description')
    ])
    expect(result.data.description).toEqual('initial description')
  })

  it('should toggle lock', () => {
    const result = playActions([
      actions.fetch(1, 1),
      actions.receive(survey),
      actions.updateLock(true)
    ])
    expect(result.data.locked).toEqual(true)
  })
})
