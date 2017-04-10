// @flow
import React, { Component, PureComponent, PropTypes } from 'react'
import { connect } from 'react-redux'
import { withRouter, Link } from 'react-router'
import values from 'lodash/values'
import * as actions from '../../actions/surveys'
import * as surveyActions from '../../actions/survey'
import * as projectActions from '../../actions/project'
import { AddButton, Card, EmptyPage, UntitledIfEmpty } from '../ui'
import { ConfirmationModal } from '../ui/ConfirmationModal'
import * as channelsActions from '../../actions/channels'
import * as respondentActions from '../../actions/respondents'
import RespondentsChart from '../respondents/RespondentsChart'
import SurveyStatus from './SurveyStatus'
import * as RespondentsChartCount from '../respondents/RespondentsChartCount'
import * as routes from '../../routes'

class SurveyIndex extends Component {
  static propTypes = {
    dispatch: PropTypes.func,
    router: PropTypes.object,
    projectId: PropTypes.any.isRequired,
    project: PropTypes.object,
    surveys: PropTypes.array,
    respondentsStats: PropTypes.object.isRequired
  }

  componentWillMount() {
    const { dispatch, projectId } = this.props

    // Fetch project for title
    dispatch(projectActions.fetchProject(projectId))

    dispatch(actions.fetchSurveys(projectId))
    .then(value => {
      for (const surveyId in value) {
        dispatch(respondentActions.fetchRespondentsStats(projectId, surveyId))
      }
    })
    dispatch(channelsActions.fetchChannels())
  }

  newSurvey() {
    const { dispatch, projectId, router } = this.props
    dispatch(surveyActions.createSurvey(projectId)).then(survey =>
      router.push(routes.surveyEdit(projectId, survey))
    )
  }

  deleteSurvey = (survey: Survey) => {
    const deleteConfirmationModal: ConfirmationModal = this.refs.deleteConfirmationModal
    deleteConfirmationModal.open({
      modalText: <span>
        <p>Are you sure you want to delete the survey <b><UntitledIfEmpty text={survey.name} entityName='survey' /></b>?</p>
        <p>All the respondent information will be lost and cannot be undone.</p>
      </span>,
      onConfirm: () => {
        const { dispatch } = this.props
        dispatch(surveyActions.deleteSurvey(survey))
      }
    })
  }

  render() {
    const { surveys, respondentsStats, project } = this.props

    if (!surveys) {
      return (
        <div>Loading surveys...</div>
      )
    }

    const readOnly = !project || project.readOnly

    let addButton = null
    if (!readOnly) {
      addButton = (
        <AddButton text='Add survey' onClick={() => this.newSurvey()} />
      )
    }

    return (
      <div>
        {addButton}
        { surveys.length == 0
        ? <EmptyPage icon='assignment_turned_in' title='You have no surveys on this project' onClick={(e) => this.newSurvey(e)} />
        : <div className='row'>
          { surveys.map(survey => (
            <SurveyCard survey={survey} completedByDate={respondentsStats[survey.id]} onDelete={this.deleteSurvey} key={survey.id} />
          )) }
        </div>
        }
        <ConfirmationModal ref='deleteConfirmationModal' confirmationText='DELETE' header='Delete survey' showCancel />
      </div>
    )
  }
}

const mapStateToProps = (state, ownProps) => {
  // Right now we show all surveys: they are not paginated nor sorted
  let surveys = state.surveys.items
  if (surveys) {
    surveys = values(surveys)
  }
  return {
    projectId: ownProps.params.projectId,
    project: state.project.data,
    surveys,
    channels: state.channels.items,
    respondentsStats: state.respondentsStats
  }
}

export default withRouter(connect(mapStateToProps)(SurveyIndex))

class SurveyCard extends PureComponent {
  props: {
    completedByDate: Object,
    survey: Survey,
    onDelete: (survey: Survey) => void
  };

  render() {
    const { survey, completedByDate, onDelete } = this.props
    let cumulativeCount = []
    let reached = 0

    if (survey && completedByDate) {
      const data = completedByDate.respondentsByDate
      const target = completedByDate.totalQuota || completedByDate.cutoff || completedByDate.totalRespondents
      cumulativeCount = RespondentsChartCount.cumulativeCount(data, target)
      if (survey.state == 'running' || survey.state == 'completed') {
        reached = RespondentsChartCount.respondentsReachedPercentage(data, target)
      }
    }

    var deleteButton = null
    if (survey.state != 'running') {
      const onDeleteClick = (e) => {
        e.preventDefault()
        onDelete(survey)
      }

      deleteButton =
        <a onClick={onDeleteClick} className='right card-hover grey-text'>
          <i className='material-icons'>delete</i>
        </a>
    }

    return (
      <div className='col s12 m6 l4'>
        <Link className='survey-card' to={routes.showOrEditSurvey(survey)}>
          <Card>
            <div className='card-content'>
              <div className='grey-text'>
                { reached + '% of target completed' }
              </div>
              <div className='card-chart'>
                <RespondentsChart completedByDate={cumulativeCount} />
              </div>
              <div className='card-status'>
                <span className='card-title truncate' title={survey.name}>
                  <UntitledIfEmpty text={survey.name} entityName='survey' />
                  {deleteButton}
                </span>
                <SurveyStatus survey={survey} />
              </div>
            </div>
          </Card>
        </Link>
      </div>
    )
  }
}
