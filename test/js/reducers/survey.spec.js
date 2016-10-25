/* eslint-env mocha */
import expect from 'expect'
import reducer from '../../../web/static/js/reducers/survey'
import * as actions from '../../../web/static/js/actions/survey'
import each from 'lodash/each'

describe('survey reducer', () => {
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

  it('receives a survey', () => {
    const state = playActions([
      actions.fetch(1, 1),
      actions.receive(survey)
    ])
    expect(state.fetching).toEqual(false)
    expect(state.data).toEqual(survey)
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
        surveyId: 1
      },
      data: null
    })
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
        surveyId: 2
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
      fetching: true,
      data: null
    })
  })

  it('should toggle a single day preserving the others', () => {
    const result = reducer(survey, actions.toggleDay('wed'))
    expect(result.scheduleDayOfWeek)
    .toEqual({'sun': true, 'mon': true, 'tue': true, 'wed': false, 'thu': true, 'fri': true, 'sat': true})
  })
})

const survey = {
  'id': 1,
  'projectId': 1,
  'name': 'Foo',
  'cutoff': 123,
  'state': 'ready',
  'questionnaireId': 1,
  'scheduleDayOfWeek': {'sun': true, 'mon': true, 'tue': true, 'wed': true, 'thu': true, 'fri': true, 'sat': true},
  'scheduleStartTime': '02:00:00',
  'scheduleEndTime': '06:00:00',
  'channels': [1],
  'respondentsCount': 2
}
