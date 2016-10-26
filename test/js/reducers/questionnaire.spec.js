/* eslint-env mocha */
import expect from 'expect'
import assert from 'assert'
import each from 'lodash/each'
import find from 'lodash/find'
import deepFreeze from '../../../web/static/vendor/js/deepFreeze'
import reducer, { buildNewStep } from '../../../web/static/js/reducers/questionnaire'
import * as actions from '../../../web/static/js/actions/questionnaire'

describe('questionnaire reducer', () => {
  const initialState = reducer(undefined, {})

  const playActions = (actions) => {
    return playActionsFromState(initialState, actions)
  }

  const playActionsFromState = (state, actions) => {
    let resultState = state
    each(actions, (a) => {
      resultState = reducer(resultState, a)
    })
    return resultState
  }

  it('has a sane initial state', () => {
    expect(initialState.fetching).toEqual(false)
    expect(initialState.filter).toEqual(null)
    expect(initialState.data).toEqual(null)
  })

  it('receives a questionnaire', () => {
    const state = playActions([
      actions.fetch(1, 1),
      actions.receive(questionnaire)
    ])
    expect(state.fetching).toEqual(false)
    expect(state.data).toEqual(questionnaire)
  })

  it('should fetch', () => {
    assert(!actions.shouldFetch({fetching: true, filter: {projectId: 1, questionnaireId: 1}}, 1, 1))
    assert(actions.shouldFetch({fetching: true, filter: null}, 1, 1))
    assert(actions.shouldFetch({fetching: true, filter: {projectId: 1, questionnaireId: 1}}, 2, 2))
    assert(actions.shouldFetch({fetching: false, filter: null}, 1, 1))
    assert(actions.shouldFetch({fetching: false, filter: {projectId: 1, questionnaireId: 1}}, 1, 1))
  })

  it('fetches a questionnaire', () => {
    const state = playActions([
      actions.fetch(1, 1)
    ])

    expect(state).toEqual({
      ...state,
      fetching: true,
      filter: {
        projectId: 1,
        questionnaireId: 1
      },
      data: null
    })
  })

  it('clears data when fetching a different questionnaire', () => {
    const state = playActions([
      actions.fetch(1, 1),
      actions.receive(questionnaire),
      actions.fetch(2, 2)
    ])

    expect(state).toEqual({
      ...state,
      fetching: true,
      filter: {
        projectId: 2,
        questionnaireId: 2
      },
      data: null
    })
  })

  it('keeps old data when fetching new data for the same filter', () => {
    const state = playActions([
      actions.fetch(1, 1),
      actions.receive(questionnaire),
      actions.fetch(1, 1)
    ])

    expect(state).toEqual({
      ...state,
      fetching: true,
      data: questionnaire
    })
  })

  it('ignores data received based on different filter', () => {
    const state = playActions([
      actions.fetch(2, 2),
      actions.receive(questionnaire)
    ])

    expect(state).toEqual({
      ...state,
      fetching: true,
      data: null
    })
  })

  it('should update questionnaire with new name', () => {
    const result = playActions([
      actions.fetch(1, 1),
      actions.receive(questionnaire),
      actions.changeName('Some other name')
    ])

    expect(result.data.name).toEqual('Some other name')
  })

  it('should change to a single mode', () => {
    const result = playActions([
      actions.fetch(1, 1),
      actions.receive(questionnaire),
      actions.changeModes('IVR')
    ])

    expect(result.data.modes.length).toEqual(1)
    expect(result.data.modes).toEqual(['IVR'])
  })

  it('should change to multiple modes', () => {
    const result = playActions([
      actions.fetch(1, 1),
      actions.receive(questionnaire),
      actions.changeModes('SMS,IVR')
    ])

    /* Expectations on arrays must include a check for length
    because for JS 'Foo,Bar' == ['Foo', 'Bar']        -_- */
    expect(result.data.modes.length).toEqual(2)
    expect(result.data.modes).toEqual(['SMS', 'IVR'])
  })

  it('should add step', () => {
    const preState = playActions([
      actions.fetch(1, 1),
      actions.receive(questionnaire)
    ])

    const resultState = playActionsFromState(preState, [
      actions.addStep('multiple-choice')
    ])

    const newStep = resultState.data.steps[resultState.data.steps.length - 1]

    expect(resultState.data.steps.length).toEqual(preState.data.steps.length + 1)
    expect(newStep.title).toEqual(buildNewStep('multiple-choice').title)
  })

  it('should initialize for the questionnaire creation use case', () => {
    const result = reducer(initialState, actions.newQuestionnaire(123))
    const questionnaire = result.data

    expect(questionnaire)
    .toEqual({
      id: null,
      name: '',
      modes: ['SMS'],
      projectId: 123,
      steps: []
    })
  })

  it('should update step title', () => {
    const preState = playActions([
      actions.fetch(1, 1),
      actions.receive(questionnaire)
    ])

    const resultState = playActionsFromState(preState, [
      actions.changeStepTitle('b6588daa-cd81-40b1-8cac-ff2e72a15c15', 'New title')
    ])

    const step = find(resultState.data.steps, s => s.id === 'b6588daa-cd81-40b1-8cac-ff2e72a15c15')
    expect(step.title).toEqual('New title')
  })

  it('should update step prompt sms', () => {
    const preState = playActions([
      actions.fetch(1, 1),
      actions.receive(questionnaire)
    ])

    const resultState = playActionsFromState(preState, [
      actions.changeStepPromptSms('b6588daa-cd81-40b1-8cac-ff2e72a15c15', 'New prompt')]
    )

    const step = find(resultState.data.steps, s => s.id === 'b6588daa-cd81-40b1-8cac-ff2e72a15c15')
    expect(step.prompt.sms).toEqual('New prompt')
  })

  it('should update step store', () => {
    const preState = playActions([
      actions.fetch(1, 1),
      actions.receive(questionnaire)
    ])

    const resultState = playActionsFromState(preState, [
      actions.changeStepStore('b6588daa-cd81-40b1-8cac-ff2e72a15c15', 'New store')]
    )

    const step = find(resultState.data.steps, s => s.id === 'b6588daa-cd81-40b1-8cac-ff2e72a15c15')
    expect(step.store).toEqual('New store')
  })

  it('should delete step', () => {
    const preState = playActions([
      actions.fetch(1, 1),
      actions.receive(questionnaire)
    ])

    const preSteps = preState.data.steps

    const resultState = playActionsFromState(preState, [
      actions.deleteStep('b6588daa-cd81-40b1-8cac-ff2e72a15c15')
    ])

    const steps = resultState.data.steps

    const deletedStep = find(resultState.data.steps, s => s.id === 'b6588daa-cd81-40b1-8cac-ff2e72a15c15')

    expect(steps.length).toEqual(preSteps.length - 1)
    expect(deletedStep).toEqual(null)
    expect(steps[0].title).toEqual('Do you smoke?')
  })

  it('should add choice', () => {
    const preState = playActions([
      actions.fetch(1, 1),
      actions.receive(questionnaire)
    ])

    const resultState = playActionsFromState(preState, [
      actions.addChoice('b6588daa-cd81-40b1-8cac-ff2e72a15c15')]
    )

    const step = find(resultState.data.steps, s => s.id === 'b6588daa-cd81-40b1-8cac-ff2e72a15c15')
    expect(step.choices.length).toEqual(3)
    expect(step.choices[2].value).toEqual('')
  })

  it('should delete choice', () => {
    const preState = playActions([
      actions.fetch(1, 1),
      actions.receive(questionnaire)
    ])

    const resultState = playActionsFromState(preState, [
      actions.deleteChoice('b6588daa-cd81-40b1-8cac-ff2e72a15c15', 1)]
    )

    const step = find(resultState.data.steps, s => s.id === 'b6588daa-cd81-40b1-8cac-ff2e72a15c15')
    expect(step.choices.length).toEqual(1)
    expect(step.choices[0].value).toEqual('Yes')
  })

  it('should modify choice', () => {
    const preState = playActions([
      actions.fetch(1, 1),
      actions.receive(questionnaire)
    ])

    const resultState = playActionsFromState(preState, [
      actions.changeChoice('17141bea-a81c-4227-bdda-f5f69188b0e7', 1, 'Maybe', 'M,MB, 3')
    ])

    const step = find(resultState.data.steps, s => s.id === '17141bea-a81c-4227-bdda-f5f69188b0e7')
    expect(step.choices.length).toEqual(2)
    expect(step.choices[1]).toEqual({
      value: 'Maybe',
      responses: [
        'M',
        'MB',
        '3'
      ]
    })
  })
})

const questionnaire = deepFreeze({
  'steps': [
    {
      'type': 'multiple-choice',
      'title': 'Do you smoke?',
      'store': 'Smokes',
      'id': '17141bea-a81c-4227-bdda-f5f69188b0e7',
      'choices': [
        {
          'value': 'Yes',
          'responses': [
            'Yes',
            'Y',
            '1'
          ]
        },
        {
          'value': 'No',
          'responses': [
            'No',
            'N',
            '1'
          ]
        }
      ],
      'prompt': {
        'sms': ''
      }
    },
    {
      'type': 'multiple-choice',
      'title': 'Do you exercise?',
      'store': 'Exercises',
      'id': 'b6588daa-cd81-40b1-8cac-ff2e72a15c15',
      'choices': [
        {
          'value': 'Yes',
          'responses': [
            'Yes',
            'Y',
            '1'
          ]
        },
        {
          'value': 'No',
          'responses': [
            'No',
            'N',
            '1'
          ]
        }
      ],
      'prompt': {
        'sms': ''
      }
    }
  ],
  'projectId': 1,
  'name': 'Foo',
  'modes': [
    'SMS'
  ],
  'id': 1
})
