import * as actions from '../actions/survey'

export default (state = {}, action) => {
  switch (action.type) {
    case actions.RECEIVE_SURVEY_RETRIES_HISTOGRAMS:
      return {
        ...state,
        surveyId: action.surveyId,
        histograms: action.response
      }
    default:
      return state
  }
}
