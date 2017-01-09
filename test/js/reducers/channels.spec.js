/* eslint-env mocha */
// @flow
import expect from 'expect'
import reducer from '../../../web/static/js/reducers/channels'

describe('channels reducer', () => {
  const initialState = reducer(undefined, {})

  it('has a sane initial state', () => {
    expect(initialState).toEqual({})
  })
})
