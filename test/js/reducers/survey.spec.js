/* eslint-env mocha */
import expect from 'expect'
import assert from 'assert'
import each from 'lodash/each'
import reducer, {surveyReducer} from '../../../web/static/js/reducers/survey'
import * as actions from '../../../web/static/js/actions/survey'

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

  it('should fetch', () => {
    assert(!actions.shouldFetch({fetching: true, filter: {projectId: 1, id: 1}}, 1, 1))
    assert(actions.shouldFetch({fetching: true, filter: null}, 1, 1))
    assert(actions.shouldFetch({fetching: true, filter: {projectId: 1, id: 1}}, 2, 2))
    assert(actions.shouldFetch({fetching: false, filter: null}, 1, 1))
    assert(actions.shouldFetch({fetching: false, filter: {projectId: 1, id: 1}}, 1, 1))
  })

  it('fetches a survey', () => {
    const state = playActions([
      actions.fetching(1, 1)
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
      actions.fetching(1, 1),
      actions.receive(survey)
    ])
    expect(state.fetching).toEqual(false)
    expect(state.data).toEqual(survey)
  })

  it('clears data when fetching a different survey', () => {
    const state = playActions([
      actions.fetching(1, 1),
      actions.receive(survey),
      actions.fetching(2, 2)
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
      actions.fetching(1, 1),
      actions.receive(survey),
      actions.fetching(1, 1)
    ])

    expect(state).toEqual({
      ...state,
      fetching: true,
      data: survey
    })
  })

  it('ignores data received based on different filter', () => {
    const state = playActions([
      actions.fetching(2, 2),
      actions.receive(survey)
    ])

    expect(state).toEqual({
      ...state,
      filter: {projectId: 2, id: 2},
      fetching: true,
      data: null
    })
  })

  it('should toggle a single day preserving the others', () => {
    const result = surveyReducer(survey, actions.toggleDay('wed'))
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
