import isEqual from 'lodash/isEqual'
import toInteger from 'lodash/toInteger'

const initialState = {
  fetching: false,
  filter: null,
  data: null
}

const defaultFilterProvider = (data) => ({
  projectId: toInteger(data.projectId),
  id: data.id == null ? null : toInteger(data.id)
})

export default (actions, dataReducer, filterProvider = defaultFilterProvider) => (state = initialState, action) => {
  switch (action.type) {
    case actions.FETCH: return fetch(state, action, filterProvider)
    case actions.RECEIVE: return receive(state, action, filterProvider)
    default: return {
      ...state,
      data: state.data == null ? null : dataReducer(state.data, action)
    }
  }
}

const receive = (state, action, filterProvider) => {
  const data = action.data
  const dataFilter = filterProvider(data)

  if (isEqual(state.filter, dataFilter)) {
    return {
      ...state,
      fetching: false,
      data: data
    }
  }

  return state
}

const fetch = (state, action, filterProvider) => {
  const newFilter = filterProvider(action)

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
