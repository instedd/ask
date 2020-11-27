import React, { Component, PropTypes } from 'react'
import { connect } from 'react-redux'
import { withRouter } from 'react-router'
import { ScrollToTopButton, CollectionItem, ScrollToLink, Tooltip, PositionFixer } from '../ui'
import SurveyWizardPanelSurveyStep from './SurveyWizardPanelSurveyStep'
import SurveyWizardQuestionnaireStep from './SurveyWizardQuestionnaireStep'
import SurveyWizardRespondentsStep from './SurveyWizardRespondentsStep'
import SurveyWizardModeStep from './SurveyWizardModeStep'
import SurveyWizardScheduleStep from './SurveyWizardScheduleStep'
import SurveyWizardCutoffStep from './SurveyWizardCutoffStep'
import SurveyWizardComparisonsStep from './SurveyWizardComparisonsStep'
import flatten from 'lodash/flatten'
import uniq from 'lodash/uniq'
import sumBy from 'lodash/sumBy'
import values from 'lodash/values'
import every from 'lodash/every'
import { launchSurvey } from '../../api'
import * as routes from '../../routes'
import { translate } from 'react-i18next'

class SurveyForm extends Component {
  static propTypes = {
    t: PropTypes.func,
    projectId: PropTypes.any.isRequired,
    survey: PropTypes.object.isRequired,
    surveyId: PropTypes.any.isRequired,
    router: PropTypes.object.isRequired,
    questionnaires: PropTypes.object,
    questionnaire: PropTypes.object,
    respondentGroups: PropTypes.object,
    respondentGroupsUploading: PropTypes.bool,
    respondentGroupsUploadingExisting: PropTypes.object,
    invalidRespondents: PropTypes.object,
    invalidGroup: PropTypes.bool,
    channels: PropTypes.object,
    errors: PropTypes.object,
    readOnly: PropTypes.bool.isRequired,
    cutOffConfigValid: PropTypes.bool
  }

  componentDidMount() {
    window.scrollTo(0, 0)
    $('.scrollspy').scrollSpy()
  }

  allModesHaveAChannel(modes, channels) {
    const selectedTypes = channels.map(channel => channel.mode)
    modes = uniq(flatten(modes))
    return modes.filter(mode => selectedTypes.indexOf(mode) != -1).length == modes.length
  }

  launchSurvey() {
    const { projectId, surveyId, router } = this.props
    launchSurvey(projectId, surveyId)
      .then(() => router.push(routes.survey(projectId, surveyId)))
  }

  questionnairesValid(ids, questionnaires) {
    return every(ids, id => questionnaires[id] && questionnaires[id].valid)
  }

  questionnairesMatchModes(modes, ids, questionnaires) {
    return every(modes, mode =>
      every(mode, m =>
        ids && every(ids, id =>
          questionnaires[id] && questionnaires[id].modes && questionnaires[id].modes.indexOf(m) != -1)))
  }

  render() {
    const { survey, projectId, questionnaires, channels, respondentGroups, respondentGroupsUploading, respondentGroupsUploadingExisting,
            invalidRespondents, invalidGroup, errors, questionnaire, readOnly, t, cutOffConfigValid } = this.props
    const questionnaireStepCompleted = survey.questionnaireIds != null && survey.questionnaireIds.length > 0 && this.questionnairesValid(survey.questionnaireIds, questionnaires)
    const respondentsStepCompleted = respondentGroups && Object.keys(respondentGroups).length > 0 &&
      every(values(respondentGroups), group => {
        return group.channels.length > 0 && this.allModesHaveAChannel(survey.mode, group.channels)
      })

    const modeStepCompleted = survey.mode != null && survey.mode.length > 0 && this.questionnairesMatchModes(survey.mode, survey.questionnaireIds, questionnaires)
    const isPanelSurveyStepCompleted = questionnaireStepCompleted
    const cutoffStepCompleted = cutOffConfigValid && questionnaireStepCompleted
    const validRetryConfiguration = !errors || (!errors.smsRetryConfiguration && !errors.ivrRetryConfiguration && !errors.fallbackDelay)
    const scheduleStepCompleted =
      survey.schedule != null &&
      survey.schedule.dayOfWeek != null && (
        survey.schedule.dayOfWeek.sun ||
        survey.schedule.dayOfWeek.mon ||
        survey.schedule.dayOfWeek.tue ||
        survey.schedule.dayOfWeek.wed ||
        survey.schedule.dayOfWeek.thu ||
        survey.schedule.dayOfWeek.fri ||
        survey.schedule.dayOfWeek.sat
      ) && validRetryConfiguration
    let comparisonsStepCompleted = false

    const mandatorySteps = [isPanelSurveyStepCompleted, questionnaireStepCompleted, modeStepCompleted, respondentsStepCompleted, scheduleStepCompleted, cutoffStepCompleted]
    if (survey.comparisons.length > 0) {
      comparisonsStepCompleted = sumBy(survey.comparisons, c => c.ratio) == 100
      mandatorySteps.push(comparisonsStepCompleted)
    }

    const numberOfCompletedSteps = mandatorySteps.filter(item => item == true).length
    const allStepsCompleted = mandatorySteps.filter(item => item == true).length == mandatorySteps.length
    const percentage = `${(100 / mandatorySteps.length * numberOfCompletedSteps).toFixed(0)}%`

    let launchComponent = null
    if (survey.state == 'ready' && !readOnly && allStepsCompleted) {
      launchComponent = (
        <Tooltip text={t('Launch survey')}>
          <a className='btn-floating btn-large waves-effect waves-light green right mtop' style={{top: '90px', left: '-5%'}} onClick={() => this.launchSurvey()}>
            <i className='material-icons'>play_arrow</i>
          </a>
        </Tooltip>
      )
    }

    // We make most steps to be "read only" (that is, non-editable) if the server said that survey
    // is "read only" (this is for a reader user) or if the survey has already started (in which
    // case there's no point in choosing a different questionnaire and so on).
    //
    // However, for the respondents step we distinguish between "read only" and "survey started",
    // because a non-reader user can still add more respondents to an existing survey, though
    // she can, for example, change their channel.
    const surveyStarted = survey.state == 'running' || survey.state == 'terminated'

    return (
      <div className='row'>
        <div className='col s12 m4'>
          <PositionFixer offset={60}>
            <ul className='collection with-header wizard'>
              <li className='collection-header'>
                <h5>{t('Progress')}<span className='right'>{percentage}</span></h5>
                <p>{t('Complete the following tasks to get your Survey ready.')}</p>
                <div className='progress'>
                  <div className='determinate' style={{ width: percentage }} />
                </div>
              </li>
              {launchComponent}
              <CollectionItem path='#panel_survey' icon='replay' text={t('Repeat survey')} completed={isPanelSurveyStepCompleted} />
              <CollectionItem path='#questionnaire' icon='assignment' text={t('Select a questionnaire')} completed={!!questionnaireStepCompleted} />
              <CollectionItem path='#channels' icon='settings_input_antenna' text={t('Select mode')} completed={!!modeStepCompleted} />
              <CollectionItem path='#respondents' icon='group' text={t('Upload your respondents list')} completed={!!respondentsStepCompleted} />
              <CollectionItem path='#schedule' icon='today' text={t('Setup a schedule')} completed={!!scheduleStepCompleted} />
              <CollectionItem path='#cutoff' icon='remove_circle' text={t('Setup cutoff rules')} completed={!!cutoffStepCompleted} />
              {/* <CollectionItem path={`#`} icon='attach_money' text={t('Assign incentives')} completed={cutoffStepCompleted} /> */}
              {survey.comparisons.length > 0
                ? <CollectionItem path='#comparisons' icon='call_split' text={t('Comparisons')} completed={!!comparisonsStepCompleted} />
              : ''}
            </ul>
          </PositionFixer>
        </div>
        <div className='col s12 m7 offset-m1 wizard-content'>
          <div id='panel_survey' className='row scrollspy'>
            <SurveyWizardPanelSurveyStep survey={survey} readOnly={readOnly || surveyStarted} />
            <ScrollToLink target='#questionnaire'>{t('NEXT: Select Questionnaire')}</ScrollToLink>
          </div>
          <div id='questionnaire' className='row scrollspy'>
            <SurveyWizardQuestionnaireStep projectId={projectId} survey={survey} questionnaires={questionnaires} readOnly={readOnly || surveyStarted} />
            <ScrollToLink target='#channels'>{t('NEXT: Select Mode')}</ScrollToLink>
          </div>
          <div id='channels' className='row scrollspy'>
            <SurveyWizardModeStep survey={survey} questionnaires={questionnaires} readOnly={readOnly || surveyStarted} respondentGroups={respondentGroups} />
            <ScrollToLink target='#respondents'>{t('NEXT: Upload your respondents list')}</ScrollToLink>
          </div>
          <div id='respondents' className='row scrollspy'>
            <SurveyWizardRespondentsStep projectId={projectId} survey={survey} channels={channels} respondentGroups={respondentGroups} respondentGroupsUploading={respondentGroupsUploading} respondentGroupsUploadingExisting={respondentGroupsUploadingExisting} invalidRespondents={invalidRespondents} invalidGroup={invalidGroup} readOnly={readOnly} surveyStarted={surveyStarted} />
            <ScrollToLink target='#schedule'>{t('NEXT: Setup a Schedule')}</ScrollToLink>
          </div>
          <div id='schedule' className='row scrollspy'>
            <SurveyWizardScheduleStep survey={survey} readOnly={readOnly || surveyStarted} />
            <ScrollToLink target='#cutoff'>{t('NEXT: Setup cutoff rules')}</ScrollToLink>
          </div>
          <div id='cutoff' className='row scrollspy'>
            <SurveyWizardCutoffStep survey={survey} questionnaire={questionnaire} readOnly={readOnly || surveyStarted} />
            {survey.comparisons.length > 0
            ? <ScrollToLink target='#comparisons'>{t('NEXT: Comparisons')}</ScrollToLink>
            : ''}
          </div>
          {survey.comparisons.length > 0
            ? <div id='comparisons' className='row scrollspy'>
              <SurveyWizardComparisonsStep survey={survey} readOnly={readOnly || surveyStarted} questionnaires={questionnaires} />
            </div>
          : ''}
          <ScrollToTopButton />
        </div>
      </div>
    )
  }
}

const mapStateToProps = (state, ownProps) => {
  return ({
    surveyId: ownProps.params.surveyId,
    errors: state.survey.errorsByPath,
    cutOffConfigValid: state.ui.data.surveyWizard.cutOffConfigValid
  })
}

export default translate()(withRouter(connect(mapStateToProps)(SurveyForm)))
