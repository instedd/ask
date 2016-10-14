import React, { Component } from 'react'
import { connect } from 'react-redux'
import { withRouter } from 'react-router'
import * as actions from '../actions/surveys'
import * as respondentActions from '../actions/respondents'
import RespondentsChart from '../components/RespondentsChart'
import * as RespondentsChartCount from '../components/RespondentsChartCount'
import * as routes from '../routes'

class SurveyShow extends Component {
  componentDidMount() {
    const { dispatch, projectId, surveyId, router } = this.props
    if (projectId && surveyId) {
      dispatch(actions.fetchSurvey(projectId, surveyId))
        .then((survey) => {
          if (survey.state === 'not_ready') {
            router.replace(routes.editSurvey(projectId, survey.id))
          }
        })
      dispatch(respondentActions.fetchRespondentsStats(projectId, surveyId))
    }
  }

  respondentsReached(completedByDate, targetValue) {
    const reached = completedByDate.length === 0 ? 0 : this.cumulativeCountFor(completedByDate[completedByDate.length - 1].date, completedByDate)
    return reached + '/' + targetValue
  }

  render() {
    const { survey, respondentsStats, completedByDate, targetValue } = this.props
    const cumulativeCount = RespondentsChartCount.cumulativeCount(completedByDate, targetValue)

    if (!survey || !completedByDate) {
      return <p>Loading...</p>
    }

    return (
      <div>
        <div className='row'>
          <div className='col s12 m8'>
            <div className='card'>
              <div className='card-table-title'>
                { survey.name }
              </div>
              <div className='card-table'>
                <table>
                  <thead>
                    <tr>
                      <th>Pending</th>
                      <th>Active</th>
                      <th>Completed</th>
                      <th>Failed</th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr>
                      <td>{ respondentsStats.pending }</td>
                      <td>{ respondentsStats.active }</td>
                      <td>{ respondentsStats.completed }</td>
                      <td>{ respondentsStats.failed }</td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </div>
          </div>
          <div className='col s12 m4'>
            <RespondentsChart completedByDate={cumulativeCount} />
          </div>
        </div>
      </div>
    )
  }
}

const mapStateToProps = (state, ownProps) => {
  const respondentsStatsRoot = state.respondentsStats[ownProps.params.surveyId]

  let respondentsStats = {}
  let completedRespondentsByDate = []
  let targetValue = 1

  if (respondentsStatsRoot) {
    respondentsStats = respondentsStatsRoot.respondentsByState
    completedRespondentsByDate = respondentsStatsRoot.completedByDate.respondentsByDate
    targetValue = respondentsStatsRoot.completedByDate.targetValue
  }

  return ({
    projectId: ownProps.params.projectId,
    project: state.projects[ownProps.params.projectId] || {},
    surveyId: ownProps.params.surveyId,
    survey: state.surveys[ownProps.params.surveyId] || {},
    respondentsStats: respondentsStats,
    completedByDate: completedRespondentsByDate,
    targetValue: targetValue
  })
}

export default withRouter(connect(mapStateToProps)(SurveyShow))
