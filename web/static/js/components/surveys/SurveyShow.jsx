// @flow
import React, { Component } from 'react'
import { connect } from 'react-redux'
import { withRouter } from 'react-router'
import * as actions from '../../actions/survey'
import * as questionnaireActions from '../../actions/questionnaire'
import * as respondentActions from '../../actions/respondents'
import RespondentsChart from '../respondents/RespondentsChart'
import SurveyStatus from './SurveyStatus'
import * as RespondentsChartCount from '../respondents/RespondentsChartCount'
import * as routes from '../../routes'
import { Tooltip, ConfirmationModal, UntitledIfEmpty } from '../ui'
import { stopSurvey } from '../../api'
import capitalize from 'lodash/capitalize'
import { modeLabel } from '../../questionnaire.mode'

class SurveyShow extends Component {
  static propTypes = {
    dispatch: React.PropTypes.func,
    router: React.PropTypes.object,
    project: React.PropTypes.object,
    projectId: React.PropTypes.string.isRequired,
    surveyId: React.PropTypes.string.isRequired,
    survey: React.PropTypes.object,
    questionnaire: React.PropTypes.object,
    respondentsStats: React.PropTypes.object,
    respondentsQuotasStats: React.PropTypes.array,
    completedByDate: React.PropTypes.array,
    contactedRespondents: React.PropTypes.number,
    target: React.PropTypes.number,
    totalRespondents: React.PropTypes.number
  }

  state: {
    responsive: boolean,
    contacted: boolean,
    uncontacted: boolean
  }

  constructor(props) {
    super(props)
    this.state = {
      responsive: false, contacted: false, uncontacted: false
    }
  }

  componentWillMount() {
    const { dispatch, projectId, surveyId } = this.props
    dispatch(actions.fetchSurveyIfNeeded(projectId, surveyId)).then(survey => {
      if (survey.questionnaires && Object.keys(survey.questionnaires).length != 0) {
        // The survey should have associated questionnaires embedded in them in the
        // latest version of the app.
      } else {
        // If not, it means these are old surveys with non-snapshot questionnaires, so we
        // fetch them here.
        let questionnaireIds = survey.questionnaireIds || []
        for (let questionnaireId of questionnaireIds) {
          dispatch(questionnaireActions.fetchQuestionnaireIfNeeded(projectId, questionnaireId))
        }
      }
    })
    dispatch(respondentActions.fetchRespondentsStats(projectId, surveyId))
    dispatch(respondentActions.fetchRespondentsQuotasStats(projectId, surveyId))
  }

  componentDidUpdate() {
    const { survey, router } = this.props
    if (survey && survey.state == 'not_ready') {
      router.replace(routes.surveyEdit(survey.projectId, survey.id))
    }
  }

  stopSurvey() {
    const { projectId, surveyId, survey, router } = this.props
    const stopConfirmationModal = this.refs.stopConfirmationModal
    stopConfirmationModal.open({
      modalText: <span>
        <p>Are you sure you want to stop the survey <b><UntitledIfEmpty text={survey.name} entityName='survey' /></b>?</p>
      </span>,
      onConfirm: () => {
        stopSurvey(projectId, surveyId)
          .then(() => router.push(routes.surveyEdit(projectId, surveyId)))
      }
    })
  }

  iconForMode(mode: string) {
    let icon = null
    switch (mode) {
      case 'sms':
        icon = 'sms'
        break
      case 'ivr':
        icon = 'phone'
        break
      case 'mobileweb':
        icon = 'phonelink'
        break
      default:
        throw new Error(`Unhandled mode in iconForMode: ${mode}`)
    }
    return icon
  }

  letterForIndex(index) {
    return String.fromCodePoint(65 + index) // A, B, C, ...
  }

  modeFor(index: number, mode: string) {
    let type = (index == 0) ? 'Primary' : 'Fallback'
    return (
      <div className='mode' key={mode}>
        <label className='grey-text'>{type} Mode</label>
        <div>
          <i className='material-icons'>{this.iconForMode(mode)}</i>
          <span className='mode-label name'>{modeLabel(mode)}</span>
        </div>
      </div>
    )
  }

  modeForComparison(mode: string) {
    return (<div className='mode-inline-block' key={mode}>
      <i className='material-icons'>{this.iconForMode(mode)}</i>
      <span className='mode-label name'>{modeLabel(mode)}</span>
    </div>
    )
  }

  modesForComparisons(modes: string[], index) {
    let modesForComparisons = modes.map((m, index) => {
      return this.modeForComparison(m)
    })

    let modeDescriptions
    if (modesForComparisons.length == 2) {
      modeDescriptions = [
        modesForComparisons[0],
        <div className='mode-inline-block' key='0' />,
        modesForComparisons[1],
        <div className='mode-inline-block' key='1'>fallback</div>
      ]
    } else {
      modeDescriptions = modesForComparisons
    }

    const letter = this.letterForIndex(index)
    return (
      <div className='mode' key={letter}>
        <label className='grey-text'>{'Mode ' + letter}</label>
        <div>
          {modeDescriptions}
        </div>
      </div>
    )
  }

  render() {
    const { survey, respondentsStats, respondentsQuotasStats, contactedRespondents, completedByDate, target, totalRespondents, project } = this.props
    const cumulativeCount = RespondentsChartCount.cumulativeCount(completedByDate, target)

    let { questionnaire } = this.props
    if (!questionnaire && survey && survey.questionnaires) {
      questionnaire = survey.questionnaires[Object.keys(survey.questionnaires)[0]]
    }

    if (!survey || !completedByDate || !questionnaire || !respondentsQuotasStats || !respondentsStats) {
      return <p>Loading...</p>
    }

    let modes
    if (survey.mode.length == 1) {
      modes = <div className='survey-modes'>
        {survey.mode[0].map((mode, index) => (this.modeFor(index, mode)))}
      </div>
    } else {
      modes = survey.mode.map((modes, index) => (<div className='survey-modes' key={String(index)}>
        {this.modesForComparisons(modes, index)}
      </div>)
      )
    }

    let table
    if (respondentsQuotasStats.length > 0) {
      table = this.quotasForAnswers(respondentsQuotasStats)
    } else {
      table = this.dispositions(respondentsStats)
    }

    const readOnly = !project || project.readOnly

    let stopComponent = null
    if (!readOnly && survey.state == 'running') {
      stopComponent = (
        <Tooltip text='Stop survey'>
          <a className='btn-floating btn-large waves-effect waves-light red right mtop' onClick={() => this.stopSurvey()}>
            <i className='material-icons'>stop</i>
          </a>
        </Tooltip>
      )
    }

    return (
      <div className='row'>
        {stopComponent}
        <ConfirmationModal modalId='survey_show_stop_modal' ref='stopConfirmationModal' confirmationText='STOP' header='Stop survey' showCancel />
        <div className='col s12 m8'>
          <h4>
            {questionnaire.name}
          </h4>
          <SurveyStatus survey={survey} />
          {table}
        </div>
        <div className='col s12 m4'>
          <div className='row survey-chart'>
            <div className='col s12'>
              <label className='grey-text'>
                { RespondentsChartCount.respondentsReachedPercentage(completedByDate, target) + '% of target completed' }
              </label>
            </div>
          </div>
          <div className='row respondent-chart'>
            <div className='col s12'>
              <RespondentsChart completedByDate={cumulativeCount} />
            </div>
          </div>
          <div className='row'>
            <div className='col s12'>
              <label className='grey-text'>
                Respondents contacted
              </label>
              <div>
                { contactedRespondents + '/' + totalRespondents }
              </div>
            </div>
          </div>
          <div className='row'>
            <div className='col s12'>
              {modes}
            </div>
          </div>
        </div>
      </div>
    )
  }

  // Round a number to two decimals, but only if the number has decimals
  round(num) {
    if (num == parseInt(num)) {
      return num
    } else {
      return num.toFixed(2)
    }
  }

  expandGroup(group) {
    let newState = {
      ...this.state
    }
    newState[group] = !this.state[group]
    this.setState(newState)
  }

  groupRows(group, groupStats) {
    let details = groupStats.detail
    let detailsKeys = Object.keys(details)
    const groupRow =
      <tr key={group}>
        <td>{capitalize(group)}</td>
        <td className='right-align'>{groupStats.count}</td>
        <td className='right-align'>
          {this.round(groupStats.percent)}%
          <a onClick={e => this.expandGroup(group)}>
            <i className='material-icons right grey-text'>expand_more</i>
          </a>
        </td>
      </tr>

    const rows = this.state[group]
    ? <tr>
      <td colSpan={100}>
        <table>
          {
            detailsKeys.map((detail) => {
              let individualStat = details[detail]
              return (
                <tr>
                  <td>{capitalize(detail)}</td>
                  <td className='right-align'>{individualStat.count}</td>
                  <td className='right-align'>{individualStat.percent}%</td>
                </tr>
              )
            })
          }
        </table>
      </td>
    </tr> : null

    return [groupRow, rows]
  }

  dispositions(respondentsStats) {
    const dispositionsGroup = ['responsive', 'contacted', 'uncontacted']
    return (
      <div className='card'>
        <div className='card-table-title'>
          Dispositions
        </div>
        <div className='card-table'>
          <table>
            <thead>
              <tr>
                <th>Status</th>
                <th className='right-align'>Quantity</th>
                <th className='right-align'>
                  Percent
                </th>
              </tr>
            </thead>
            <tbody>
              {
                dispositionsGroup.map(group => {
                  let groupStats = respondentsStats[group]
                  return this.groupRows(group, groupStats)
                })
              }
            </tbody>
          </table>
        </div>
      </div>
    )
  }

  quotasForAnswers(stats) {
    return (
      <div className='card'>
        <div className='card-table-title'>
          {stats.length} quotas for answers
        </div>
        <div className='card-table'>
          <table>
            <thead>
              <tr>
                <th>Quota</th>
                <th className='right-align'>Target</th>
                <th className='right-align'>Percent</th>
                <th className='right-align'>Full</th>
                <th className='right-align'>Partials</th>
              </tr>
            </thead>
            <tbody>
              { stats.map((stat, index) => {
                let conditions = []
                for (let key in stat.condition) {
                  conditions.push([`${key}: ${stat.condition[key]}`])
                }
                const quota = stat.quota == null ? 0 : stat.quota
                return (
                  <tr key={index}>
                    <td>
                      { conditions.map((condition, index2) => (
                        <span key={index2}>
                          {condition}
                          <br />
                        </span>
                    )) }
                    </td>
                    <td className='right-align'>{quota}</td>
                    <td className='right-align'>{quota == 0 ? '-' : `${Math.min(Math.round(stat.count * 100.0 / quota), 100)}%`}</td>
                    <td className='right-align'>{quota == 0 ? '-' : stat.full}</td>
                    <td className='right-align'>{quota == 0 ? '-' : stat.partials}</td>
                  </tr>
                )
              }) }
            </tbody>
          </table>
        </div>
      </div>
    )
  }
}

const mapStateToProps = (state, ownProps) => {
  const respondentsStatsRoot = state.respondentsStats[ownProps.params.surveyId]
  const respondentsQuotasStats = state.respondentsQuotasStats.data

  let respondentsStats = null
  let completedRespondentsByDate = []
  let contactedRespondents = 0
  let target = 1
  let totalRespondents = 1

  if (respondentsStatsRoot) {
    respondentsStats = respondentsStatsRoot.respondentsByDisposition
    completedRespondentsByDate = respondentsStatsRoot.respondentsByDate
    target = respondentsStatsRoot.totalQuota || respondentsStatsRoot.cutoff || totalRespondents
    totalRespondents = respondentsStatsRoot.totalRespondents
    contactedRespondents = totalRespondents - respondentsStatsRoot.respondentsByDisposition.uncontacted.detail.registered.count
  }

  return ({
    projectId: ownProps.params.projectId,
    project: state.project.data,
    surveyId: ownProps.params.surveyId,
    survey: state.survey.data,
    questionnaire: state.questionnaire.data,
    respondentsStats: respondentsStats,
    respondentsQuotasStats: respondentsQuotasStats,
    completedByDate: completedRespondentsByDate,
    contactedRespondents: contactedRespondents,
    target: target,
    totalRespondents: totalRespondents
  })
}

export default withRouter(connect(mapStateToProps)(SurveyShow))
