/* eslint-env mocha */
import expect from 'expect'
import assert from 'assert'
import { playActionsFromState } from '../spec_helper'
import find from 'lodash/find'
import deepFreeze from '../../../web/static/vendor/js/deepFreeze'
import reducer, { stepStoreValues, csvForTranslation } from '../../../web/static/js/reducers/questionnaire'
import * as actions from '../../../web/static/js/actions/questionnaire'

describe('questionnaire reducer', () => {
  const initialState = reducer(undefined, {})

  const playActions = playActionsFromState(initialState, reducer)

  it('has a sane initial state', () => {
    expect(initialState.fetching).toEqual(false)
    expect(initialState.filter).toEqual(null)
    expect(initialState.data).toEqual(null)
    expect(initialState.dirty).toEqual(false)
    expect(initialState.saving).toEqual(false)
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
    assert(!actions.shouldFetch({fetching: true, filter: {projectId: 1, id: 1}}, 1, 1))
    assert(actions.shouldFetch({fetching: true, filter: null}, 1, 1))
    assert(actions.shouldFetch({fetching: true, filter: {projectId: 1, id: 1}}, 2, 2))
    assert(actions.shouldFetch({fetching: false, filter: null}, 1, 1))
    assert(actions.shouldFetch({fetching: false, filter: {projectId: 1, id: 1}}, 1, 1))
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
        id: 1
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
        id: 2
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

  it('updating questionnaire should mark it as dirty', () => {
    const state = playActions([
      actions.fetch(1, 1),
      actions.receive(questionnaire),
      actions.changeName('Some other name')
    ])

    expect(state.data.name).toEqual('Some other name')

    expect(state).toEqual({
      ...state,
      dirty: true
    })
  })

  it('should be marked saving when saving', () => {
    const state = playActions([
      actions.fetch(1, 1),
      actions.receive(questionnaire),
      actions.changeName('Some other name'),
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
      actions.receive(questionnaire),
      actions.changeName('Some other name'),
      actions.saving(),
      actions.saved()
    ])

    expect(state).toEqual({
      ...state,
      saving: false,
      dirty: false
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

  it('should toggle mode', () => {
    const result = playActions([
      actions.fetch(1, 1),
      actions.receive(questionnaire),
      actions.toggleMode('ivr')
    ])

    expect(result.data.modes.length).toEqual(1)
    expect(result.data.modes).toEqual(['sms'])
  })

  it('should toggle other mode', () => {
    const result = playActions([
      actions.fetch(1, 1),
      actions.receive(questionnaire),
      actions.toggleMode('sms'),
      actions.toggleMode('ivr')
    ])

    /* Expectations on arrays must include a check for length
    because for JS 'Foo,Bar' == ['Foo', 'Bar']        -_- */
    expect(result.data.modes.length).toEqual(0)
  })

  it('should toggle modes multiple times', () => {
    const result = playActions([
      actions.fetch(1, 1),
      actions.receive(questionnaire),
      actions.toggleMode('ivr'),
      actions.toggleMode('sms'),
      actions.toggleMode('sms')
    ])

    /* Expectations on arrays must include a check for length
    because for JS 'Foo,Bar' == ['Foo', 'Bar']        -_- */
    expect(result.data.modes.length).toEqual(1)
    expect(result.data.modes).toEqual(['sms'])
  })

  it('should add step', () => {
    const preState = playActions([
      actions.fetch(1, 1),
      actions.receive(questionnaire)
    ])

    const resultState = playActionsFromState(preState, reducer)([
      actions.addStep()
    ])

    const newStep = resultState.data.steps[resultState.data.steps.length - 1]

    expect(resultState.data.steps.length).toEqual(preState.data.steps.length + 1)
    expect(newStep.type).toEqual('multiple-choice')
  })

  it('should change step type', () => {
    const preState = playActions([
      actions.fetch(1, 1),
      actions.receive(questionnaire)
    ])

    const resultState = playActionsFromState(preState, reducer)([
      actions.changeStepType('17141bea-a81c-4227-bdda-f5f69188b0e7', 'numeric')
    ])

    const resultStep = find(resultState.data.steps, s => s.id === '17141bea-a81c-4227-bdda-f5f69188b0e7')

    expect(resultState.data.steps.length).toEqual(preState.data.steps.length)
    expect(resultStep.type).toEqual('numeric')
    expect(resultStep.title).toEqual('Do you smoke?')
    expect(resultStep.store).toEqual('Smokes')
    expect(resultStep.prompt['en']).toEqual({ sms: 'Do you smoke?' })
  })

  it('should update step title', () => {
    const preState = playActions([
      actions.fetch(1, 1),
      actions.receive(questionnaire)
    ])

    const resultState = playActionsFromState(preState, reducer)([
      actions.changeStepTitle('b6588daa-cd81-40b1-8cac-ff2e72a15c15', 'New title')
    ])

    expect(resultState.data.steps.length).toEqual(preState.data.steps.length)
    const step = find(resultState.data.steps, s => s.id === 'b6588daa-cd81-40b1-8cac-ff2e72a15c15')
    expect(step.title).toEqual('New title')
  })

  it('should update step prompt sms', () => {
    const preState = playActions([
      actions.fetch(1, 1),
      actions.receive(questionnaire)
    ])

    const resultState = playActionsFromState(preState, reducer)([
      actions.changeStepPromptSms('b6588daa-cd81-40b1-8cac-ff2e72a15c15', 'New prompt')]
    )

    const step = find(resultState.data.steps, s => s.id === 'b6588daa-cd81-40b1-8cac-ff2e72a15c15')
    expect(step.prompt['en'].sms).toEqual('New prompt')
  })

  it('should update step prompt ivr', () => {
    const preState = playActions([
      actions.fetch(1, 1),
      actions.receive(questionnaire)
    ])

    const resultState = playActionsFromState(preState, reducer)([
      actions.changeStepPromptIvr('b6588daa-cd81-40b1-8cac-ff2e72a15c15', {text: 'New prompt', audioSource: 'tts'})]
    )

    const step = find(resultState.data.steps, s => s.id === 'b6588daa-cd81-40b1-8cac-ff2e72a15c15')
    expect(step.prompt['en'].ivr).toEqual({text: 'New prompt', audioSource: 'tts'})
  })

  it('should update step store', () => {
    const preState = playActions([
      actions.fetch(1, 1),
      actions.receive(questionnaire)
    ])

    const resultState = playActionsFromState(preState, reducer)([
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

    const resultState = playActionsFromState(preState, reducer)([
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

    const resultState = playActionsFromState(preState, reducer)([
      actions.addChoice('b6588daa-cd81-40b1-8cac-ff2e72a15c15')]
    )

    const step = find(resultState.data.steps, s => s.id === 'b6588daa-cd81-40b1-8cac-ff2e72a15c15')
    expect(step.choices.length).toEqual(3)
    expect(step.choices[2].value).toEqual('')
    expect(step.choices[2].responses['en']).toEqual({sms: [], ivr: []})
  })

  it('should delete choice', () => {
    const preState = playActions([
      actions.fetch(1, 1),
      actions.receive(questionnaire)
    ])

    const resultState = playActionsFromState(preState, reducer)([
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

    const resultState = playActionsFromState(preState, reducer)([
      actions.changeChoice('17141bea-a81c-4227-bdda-f5f69188b0e7', 1, 'Maybe', 'M,MB, 3', 'May', 'end')
    ])

    const step = find(resultState.data.steps, s => s.id === '17141bea-a81c-4227-bdda-f5f69188b0e7')
    expect(step.choices.length).toEqual(2)
    expect(step.choices[1].value).toEqual('Maybe')
    expect(step.choices[1].skipLogic).toEqual('end')
    expect(step.choices[1].responses['en']).toEqual({
      sms: [
        'M',
        'MB',
        '3'
      ],
      ivr: [
        'May'
      ]
    })
  })

  it('should autocomplete choice options when parameter is true', () => {
    const preState = playActions([
      actions.fetch(1, 1),
      actions.receive(questionnaire)
    ])

    const resultState = playActionsFromState(preState, reducer)([
      actions.changeChoice('17141bea-a81c-4227-bdda-f5f69188b0e7', 1, 'Maybe', 'M,MB, 3', 'May', 'end'),
      actions.addChoice('b6588daa-cd81-40b1-8cac-ff2e72a15c15'),
      actions.changeChoice('b6588daa-cd81-40b1-8cac-ff2e72a15c15', 2, 'Maybe', '', '', 'some-id', true)
    ])

    const step = find(resultState.data.steps, s => s.id === 'b6588daa-cd81-40b1-8cac-ff2e72a15c15')
    expect(step.choices.length).toEqual(3)
    expect(step.choices[2]).toEqual({
      value: 'Maybe',
      responses: {
        'en': {
          sms: [
            'M',
            'MB',
            '3'
          ],
          ivr: [
            'May'
          ]
        }
      },
      skipLogic: 'some-id'
    })
  })

  it('should not autocomplete choice options when not asked to', () => {
    const preState = playActions([
      actions.fetch(1, 1),
      actions.receive(questionnaire)
    ])

    const resultState = playActionsFromState(preState, reducer)([
      actions.changeChoice('17141bea-a81c-4227-bdda-f5f69188b0e7', 1, 'Maybe', 'M,MB, 3', 'May', 'end'),
      actions.addChoice('b6588daa-cd81-40b1-8cac-ff2e72a15c15'),
      actions.changeChoice('b6588daa-cd81-40b1-8cac-ff2e72a15c15', 2, 'Maybe', '', '', 'some-other-id', false)
    ])

    const step = find(resultState.data.steps, s => s.id === 'b6588daa-cd81-40b1-8cac-ff2e72a15c15')
    expect(step.choices.length).toEqual(3)
    expect(step.choices[2]).toEqual({
      value: 'Maybe',
      responses: {
        'en': {
          sms: [],
          ivr: []
        }
      },
      skipLogic: 'some-other-id'
    })
  })

  it('should not autocomplete choice options when there are options already set', () => {
    const preState = playActions([
      actions.fetch(1, 1),
      actions.receive(questionnaire)
    ])

    const resultState = playActionsFromState(preState, reducer)([
      actions.changeChoice('17141bea-a81c-4227-bdda-f5f69188b0e7', 1, 'Maybe', 'M,MB, 3', 'May', 'end'),
      actions.addChoice('b6588daa-cd81-40b1-8cac-ff2e72a15c15'),
      actions.changeChoice('b6588daa-cd81-40b1-8cac-ff2e72a15c15', 2, 'Maybe', 'Perhaps', '2, 3', 'some-other-id', true)
    ])

    const step = find(resultState.data.steps, s => s.id === 'b6588daa-cd81-40b1-8cac-ff2e72a15c15')
    expect(step.choices.length).toEqual(3)

    expect(step.choices[2]).toEqual({
      value: 'Maybe',
      responses: {
        'en': {
          sms: [
            'Perhaps'
          ],
          ivr: [
            '2',
            '3'
          ]
        }
      },
      skipLogic: 'some-other-id'
    })
  })

  describe('validations', () => {
    it('should validate SMS message must not be blank if "SMS" mode is on', () => {
      const preState = playActions([
        actions.fetch(1, 1),
        actions.receive(questionnaire)
      ])

      const resultState = playActionsFromState(preState, reducer)([
        actions.changeStepPromptSms('17141bea-a81c-4227-bdda-f5f69188b0e7', '')
      ])

      expect(resultState.errors).toEqual({
        'steps[0].prompt.sms': ['SMS prompt must not be blank']
      })
    })

    it('should validate voice message must not be blank if "Phone call" mode is on', () => {
      const preState = playActions([
        actions.fetch(1, 1),
        actions.receive(questionnaire)
      ])

      const resultState = playActionsFromState(preState, reducer)([
        actions.changeStepPromptIvr('17141bea-a81c-4227-bdda-f5f69188b0e7', {text: '', audioSource: 'tts'})
      ])

      expect(resultState.errors).toEqual({
        'steps[0].prompt.ivr.text': ['Voice prompt must not be blank']
      })
    })

    it('should validate there must be at least two responses', () => {
      const preState = playActions([
        actions.fetch(1, 1),
        actions.receive(questionnaire)
      ])

      const resultState = playActionsFromState(preState, reducer)([
        actions.deleteChoice('17141bea-a81c-4227-bdda-f5f69188b0e7', 0),
        actions.deleteChoice('17141bea-a81c-4227-bdda-f5f69188b0e7', 0)
      ])

      expect(resultState.errors).toEqual({
        'steps[0].choices': ['Must have at least two responses']
      })
    })

    it("should validate a response's response must not be blank", () => {
      const preState = playActions([
        actions.fetch(1, 1),
        actions.receive(questionnaire)
      ])

      const resultState = playActionsFromState(preState, reducer)([
        actions.changeChoice('17141bea-a81c-4227-bdda-f5f69188b0e7', 0, '', 'a', '1', null)
      ])

      expect(resultState.errors).toEqual({
        'steps[0].choices[0].value': ['Response must not be blank']
      })
    })

    it("should validate a response's SMS must not be blank if SMS mode is on", () => {
      const preState = playActions([
        actions.fetch(1, 1),
        actions.receive(questionnaire)
      ])

      const resultState = playActionsFromState(preState, reducer)([
        actions.changeChoice('17141bea-a81c-4227-bdda-f5f69188b0e7', 0, 'a', '', '1', null)
      ])

      expect(resultState.errors).toEqual({
        'steps[0].choices[0].sms': ['SMS must not be blank']
      })
    })

    it("should validate a response's Phone call must not be blank if Voice mode is on", () => {
      const preState = playActions([
        actions.fetch(1, 1),
        actions.receive(questionnaire)
      ])

      const resultState = playActionsFromState(preState, reducer)([
        actions.changeChoice('17141bea-a81c-4227-bdda-f5f69188b0e7', 0, 'a', 'b', '', null)
      ])

      expect(resultState.errors).toEqual({
        'steps[0].choices[0].ivr': ['"Phone call" must not be blank']
      })
    })

    it("should validate a response's Phone call must only consist of digits or # or *", () => {
      const preState = playActions([
        actions.fetch(1, 1),
        actions.receive(questionnaire)
      ])

      const resultState = playActionsFromState(preState, reducer)([
        actions.changeChoice('17141bea-a81c-4227-bdda-f5f69188b0e7', 1, 'Maybe', 'M,MB, 3', 'May', 'end'),
        actions.addChoice('b6588daa-cd81-40b1-8cac-ff2e72a15c15'),
        actions.changeChoice('b6588daa-cd81-40b1-8cac-ff2e72a15c15', 2, 'Maybe', 'A', '3, b, #, 22', 'some-other-id', false)
      ])

      const step = find(resultState.data.steps, s => s.id === 'b6588daa-cd81-40b1-8cac-ff2e72a15c15')
      expect(step.choices.length).toEqual(3)
      expect(step.choices[2]).toEqual({
        value: 'Maybe',
        responses: {
          'en': {
            sms: ['A'],
            ivr: [
              '3',
              'b',
              '#',
              '22'
            ]
          }
        },
        skipLogic: 'some-other-id'
      })
      expect(resultState.errors).toEqual({
        'steps[0].choices[1].ivr': [ '"Phone call" must only consist of single digits, "#" or "*"' ],
        'steps[1].choices[2].ivr': [ '"Phone call" must only consist of single digits, "#" or "*"' ]
      })
    })

    it("should validate a response's 'response' can't appear more than once in a same step", () => {
      const preState = playActions([
        actions.fetch(1, 1),
        actions.receive(questionnaire)
      ])

      const resultState = playActionsFromState(preState, reducer)([
        actions.changeChoice('17141bea-a81c-4227-bdda-f5f69188b0e7', 0, 'dup', 'b', '1', null),
        actions.changeChoice('17141bea-a81c-4227-bdda-f5f69188b0e7', 1, 'dup', 'c', '2', null)
      ])

      expect(resultState.errors).toEqual({
        'steps[0].choices[1].value': ['Value already used in a previous response']
      })
    })

    it("should validate a response's SMS value must not overlap other SMS values", () => {
      const preState = playActions([
        actions.fetch(1, 1),
        actions.receive(questionnaire)
      ])

      const resultState = playActionsFromState(preState, reducer)([
        actions.changeChoice('17141bea-a81c-4227-bdda-f5f69188b0e7', 0, 'a', 'b, c', '1', null),
        actions.changeChoice('17141bea-a81c-4227-bdda-f5f69188b0e7', 1, 'b', 'd, c', '2', null)
      ])

      expect(resultState.errors).toEqual({
        'steps[0].choices[1].sms': ['Value "c" already used in a previous response']
      })
    })

    it("should validate a response's IVR value must not overlap other SMS values", () => {
      const preState = playActions([
        actions.fetch(1, 1),
        actions.receive(questionnaire)
      ])

      const resultState = playActionsFromState(preState, reducer)([
        actions.changeChoice('17141bea-a81c-4227-bdda-f5f69188b0e7', 0, 'a', 'x', '1, 2', null),
        actions.changeChoice('17141bea-a81c-4227-bdda-f5f69188b0e7', 1, 'b', 'y', '3, 2', null)
      ])

      expect(resultState.errors).toEqual({
        'steps[0].choices[1].ivr': ['Value "2" already used in a previous response']
      })
    })
  })

  it('should add language selection step when adding a language', () => {
    const preState = playActions([
      actions.fetch(1, 1),
      actions.receive(questionnaire)
    ])

    const resultState = playActionsFromState(preState, reducer)([
      actions.addLanguage('fr')
    ])

    const languageSelection = resultState.data.steps[0]
    expect(languageSelection.type).toEqual('language-selection')
    expect(languageSelection.languageChoices).toInclude('fr')
  })

  it('should add a new language last inside the choices of the language selection step', () => {
    const preState = playActions([
      actions.fetch(1, 1),
      actions.receive(questionnaire),
      actions.addLanguage('en')
    ])

    const resultState = playActionsFromState(preState, reducer)([
      actions.addLanguage('de')
    ])

    const languageSelection = resultState.data.steps[0]
    expect(languageSelection.languageChoices[languageSelection.languageChoices.length - 1]).toEqual('de')
  })

  it('should remove a language inside the choices of the language selection step', () => {
    const preState = playActions([
      actions.fetch(1, 1),
      actions.receive(questionnaire),
      actions.addLanguage('en'),
      actions.addLanguage('de'),
      actions.addLanguage('es'),
      actions.addLanguage('fr')
    ])
    const preLanguageSelection = preState.data.steps[0]
    expect(preLanguageSelection.languageChoices[2]).toEqual('de')

    const resultState = playActionsFromState(preState, reducer)([
      actions.removeLanguage('de')
    ])

    const languageSelection = resultState.data.steps[0]
    expect(languageSelection.languageChoices[2]).toEqual('es')
    expect(languageSelection.languageChoices[3]).toEqual('fr')
  })

  it('should reorder correctly the languages inside the choices of the language selection step', () => {
    const preState = playActions([
      actions.fetch(1, 1),
      actions.receive(questionnaire),
      actions.addLanguage('en'),
      actions.addLanguage('es'),
      actions.addLanguage('de'),
      actions.addLanguage('fr')
    ])

    const resultState = playActionsFromState(preState, reducer)([
      actions.reorderLanguages('en', 4)
    ])

    const languageSelection = resultState.data.steps[0]
    expect(languageSelection.languageChoices[1]).toEqual('es')
    expect(languageSelection.languageChoices[2]).toEqual('de')
    expect(languageSelection.languageChoices[3]).toEqual('fr')
    expect(languageSelection.languageChoices[4]).toEqual('en')
  })

  it('should reorder correctly the languages inside the choices of the language selection step 2', () => {
    const preState = playActions([
      actions.fetch(1, 1),
      actions.receive(questionnaire),
      actions.addLanguage('en'),
      actions.addLanguage('es'),
      actions.addLanguage('de'),
      actions.addLanguage('fr')
    ])

    const resultState = playActionsFromState(preState, reducer)([
      actions.reorderLanguages('fr', 1)
    ])

    const languageSelection = resultState.data.steps[0]
    expect(languageSelection.languageChoices[1]).toEqual('fr')
    expect(languageSelection.languageChoices[2]).toEqual('en')
    expect(languageSelection.languageChoices[3]).toEqual('es')
    expect(languageSelection.languageChoices[4]).toEqual('de')
  })

  it('should add language', () => {
    const preState = playActions([
      actions.fetch(1, 1),
      actions.receive(questionnaire)
    ])

    const resultState = playActionsFromState(preState, reducer)([
      actions.addLanguage('fr')
    ])

    const languages = resultState.data.languages
    expect(languages).toInclude('fr')
  })

  it('should not add language if it was already added', () => {
    const preState = playActions([
      actions.fetch(1, 1),
      actions.receive(questionnaire)
    ])

    const resultState = playActionsFromState(preState, reducer)([
      actions.addLanguage('fr'),
      actions.addLanguage('de'),
      actions.addLanguage('fr')
    ])

    const languages = resultState.data.languages
    expect(languages.reduce((acum, lang) => (lang == 'fr') ? acum + 1 : acum, 0)).toEqual(1)
  })

  it('should remove language', () => {
    const preState = playActions([
      actions.fetch(1, 1),
      actions.receive(questionnaire)
    ])

    const state = playActionsFromState(preState, reducer)([
      actions.addLanguage('de'),
      actions.addLanguage('fr'),
      actions.addLanguage('en')
    ])

    const resultState = playActionsFromState(state, reducer)([
      actions.removeLanguage('fr')
    ])

    const languages = resultState.data.languages
    expect(languages).toNotInclude('fr')
  })

  it('should remove language and remove language selection step', () => {
    const preState = playActions([
      actions.fetch(1, 1),
      actions.receive(questionnaire)
    ])

    let oldStepsLength = preState.data.steps.length;

    const state = playActionsFromState(preState, reducer)([
      actions.addLanguage('de'),
    ])

    const resultState = playActionsFromState(state, reducer)([
      actions.removeLanguage('de')
    ])

    let steps = resultState.data.steps
    expect(steps.length).toEqual(oldStepsLength)
  })

  it('should set default language', () => {
    const preState = playActions([
      actions.fetch(1, 1),
      actions.receive(questionnaire)
    ])

    const resultState = playActionsFromState(preState, reducer)([
      actions.addLanguage('fr'),
      actions.setDefaultLanguage('fr')
    ])

    expect(resultState.data.defaultLanguage).toEqual('fr')
  })

  it('should provide valid answers for multiple-choice steps', () => {
    const questionnaire = deepFreeze({
      steps: [
        {
          type: 'multiple-choice',
          store: 'Smokes',
          choices: [{value: 'Yes'}, {value: 'No'}]
        },
        {
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

    expect(stepStoreValues(questionnaire)).toEqual({
      Smokes: ['Yes', 'No'],
      Exercises: ['Yes', 'No']
    })
  })

  describe('csv for translation', () => {
    it('should work', () => {
      const state = playActions([
        actions.fetch(1, 1),
        actions.receive(questionnaire),
        actions.addLanguage('fr'),
        actions.addLanguage('es')
      ])

      const csv = csvForTranslation(state.data)

      const expected = [
        ['"en"', '"fr"', '"es"'],
        ['"Do you smoke?"', '""', '"Fumas?"'],
        ['"Yes, Y, 1"', '""', '"Sí, S, 1"'],
        ['"No, N, 2"', '""', '"No, N, 2"'],
        ['"Do you exercise?"', '""', '"Ejercitas?"']
      ]

      console.log(csv)

      expect(csv.length).toEqual(expected.length)
      expected.forEach((row, index) => expect(csv[index]).toEqual(row))
    })
  })
})

const questionnaire = deepFreeze({
  steps: [
    {
      type: 'multiple-choice',
      title: 'Do you smoke?',
      store: 'Smokes',
      id: '17141bea-a81c-4227-bdda-f5f69188b0e7',
      choices: [
        {
          value: 'Yes',
          responses: {
            'en': {
              sms: [
                'Yes',
                'Y',
                '1'
              ],
              ivr: [
                '1'
              ]
            },
            'es': {
              sms: [
                'Sí',
                'S',
                '1'
              ],
              ivr: [
                '1'
              ]
            }
          },
          skipLogic: null
        },
        {
          value: 'No',
          responses: {
            'en': {
              sms: [
                'No',
                'N',
                '2'
              ],
              ivr: [
                '2'
              ]
            },
            'es': {
              sms: [
                'No',
                'N',
                '2'
              ],
              ivr: [
                '2'
              ]
            }
          },
          skipLogic: 'b6588daa-cd81-40b1-8cac-ff2e72a15c15'
        }
      ],
      prompt: {
        'en': {
          sms: 'Do you smoke?'
        },
        'es': {
          sms: 'Fumas?'
        }
      }
    },
    {
      type: 'multiple-choice',
      title: 'Do you exercise?',
      store: 'Exercises',
      id: 'b6588daa-cd81-40b1-8cac-ff2e72a15c15',
      choices: [
        {
          value: 'Yes',
          responses: {
            'en': {
              sms: [
                'Yes',
                'Y',
                '1'
              ],
              ivr: [
                '1'
              ]
            },
          }
        },
        {
          value: 'No',
          responses: {
            'en': {
              sms: [
                'No',
                'N',
                '2'
              ],
              ivr: [
                '2'
              ]
            }
          }
        }
      ],
      prompt: {
        'en': {
          sms: 'Do you exercise?'
        },
        'es': {
          sms: 'Ejercitas?'
        }
      }
    }
  ],
  projectId: 1,
  name: 'Foo',
  modes: [
    'sms', 'ivr'
  ],
  id: 1,
  defaultLanguage: 'en',
  languages: ['en']
})
