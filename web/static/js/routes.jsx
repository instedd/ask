import React from 'react'
import { Route, IndexRoute, IndexRedirect } from 'react-router'
import App from './components/layout/App'
import IntegrationIndex from './components/integrations/IntegrationIndex'
import ProjectIndex from './components/projects/ProjectIndex'
import SurveyEdit from './components/surveys/SurveyEdit'
import SurveyIndex from './components/surveys/SurveyIndex'
import FolderShow from './components/folders/FolderShow'
import SurveyShow from './components/surveys/SurveyShow'
import SurveySettings from './components/surveys/SurveySettings'
import SurveySimulation from './components/surveys/SurveySimulation'
import QuestionnaireIndex from './components/questionnaires/QuestionnaireIndex'
import QuestionnaireEditor from './components/questionnaires/QuestionnaireEditor'
import ChannelIndex from './components/channels/ChannelIndex'
import ProjectTabs from './components/projects/ProjectTabs'
import SurveyTabs from './components/surveys/SurveyTabs'
import RespondentIndex from './components/respondents/RespondentIndex'
import ProjectTitle from './components/projects/ProjectTitle'
import SurveyTitle from './components/surveys/SurveyTitle'
import QuestionnaireTitle from './components/questionnaires/QuestionnaireTitle'
import CollaboratorIndex from './components/collaborators/CollaboratorIndex'
import ActivityIndex from './components/activity/ActivityIndex'
import InviteConfirmation from './components/InviteConfirmation'
import ChannelEdit from './components/channels/ChannelEdit'
import ChannelPatterns from './components/channels/ChannelPatterns'
import ChannelTitle from './components/channels/ChannelTitle'
import * as questionnaireActions from './actions/questionnaire'
import ChannelTabs from './components/channels/ChannelTabs'
import ChannelNew from './components/channels/ChannelNew'
import ChannelSettings from './components/channels/ChannelSettings'
import SmsSimulator from './components/simulator/SmsSimulator'

const k = (s) => s

export default (
  <Route path='/' component={App}>
    <IndexRedirect to='projects' />

    <Route path='/projects' title={k('Projects')}>
      <IndexRoute component={ProjectIndex} />

      <Route path=':projectId' title={ProjectTitle}>
        <IndexRedirect to='surveys' />
        <Route path='folders/:folderId' components={{ body: FolderShow, tabs: ProjectTabs }} />

        <Route path='surveys'>
          <IndexRoute components={{ body: SurveyIndex, tabs: ProjectTabs }} />

          <Route path=':surveyId' title={SurveyTitle}>
            <IndexRoute components={{ body: SurveyShow, tabs: SurveyTabs }} />
            <Route path='respondents' components={{ body: RespondentIndex, tabs: SurveyTabs }} />
            <Route path='settings' components={{ body: SurveySettings, tabs: SurveyTabs }} />
            <Route path='integrations' components={{ body: IntegrationIndex, tabs: SurveyTabs }} />
            <Route path='edit' component={SurveyEdit} showSavingStatus />
            <Route path='simulation' component={SurveySimulation} />
          </Route>
        </Route>

        <Route path='questionnaires' >
          <IndexRoute components={{ body: QuestionnaireIndex, tabs: ProjectTabs }} />
          <Route path=':questionnaireId' >
            <IndexRedirect to='edit' />
          </Route>
          <Route path=':questionnaireId/edit' component={QuestionnaireEditor} title={QuestionnaireTitle} showSavingStatus undo={{state: (state) => state.questionnaire, actions: questionnaireActions}} />
        </Route>

        <Route path='collaborators' >
          <IndexRoute components={{ body: CollaboratorIndex, tabs: ProjectTabs }} />
        </Route>

        <Route path='activity' >
          <IndexRoute components={{ body: ActivityIndex, tabs: ProjectTabs }} />
        </Route>
      </Route>
    </Route>

    <Route path='confirm'>
      <IndexRoute component={InviteConfirmation} title={k('Accept invitation')} />
    </Route>

    <Route path='/channels' title={k('Channels')} >
      <IndexRoute component={ChannelIndex} />

      <Route path='new' component={ChannelNew} title='New Channel' />
      <Route path=':channelId' title={ChannelTitle} >
        <IndexRedirect to='share' />
        <Route path='share' components={{ body: ChannelEdit, tabs: ChannelTabs }} />
        <Route path='patterns' components={{ body: ChannelPatterns, tabs: ChannelTabs }} />
        <Route path='settings' components={{ body: ChannelSettings, tabs: ChannelTabs }} />
      </Route>
    </Route>

    <Route path='/simulator' title={k('Sms Simulator')} component={SmsSimulator}/>
  </Route>
)

export const root = '/'
export const projects = '/projects'
export const project = (id) => `${projects}/${id}`
export const folder = (projectId, folderId) => `${project(projectId)}/folders/${folderId}`
export const surveyIndex = (projectId) => `${project(projectId)}/surveys`
export const survey = (projectId, surveyId) => `${surveyIndex(projectId)}/${surveyId}`
export const surveySimulation = (projectId, surveyId) => `${surveyIndex(projectId)}/${surveyId}/simulation`
export const surveyRespondents = (projectId, surveyId) => `${survey(projectId, surveyId)}/respondents`
export const surveySettings = (projectId, surveyId) => `${survey(projectId, surveyId)}/settings`
export const surveyIntegrations = (projectId, surveyId) => `${survey(projectId, surveyId)}/integrations`
export const respondentsResultsCSV = (projectId, surveyId) => `/api/v1${surveyRespondents(projectId, surveyId)}/results?_format=csv`
export const respondentsDispositionHistoryCSV = (projectId, surveyId) => `/api/v1${surveyRespondents(projectId, surveyId)}/disposition_history?_format=csv`
export const respondentsIncentivesCSV = (projectId, surveyId) => `/api/v1${surveyRespondents(projectId, surveyId)}/incentives?_format=csv`
export const respondentsInteractionsCSV = (projectId, surveyId) => `/api/v1${surveyRespondents(projectId, surveyId)}/interactions?_format=csv`
export const surveyEdit = (projectId, surveyId) => `${survey(projectId, surveyId)}/edit`
export const surveyFolderNew = (projectId, surveyId) => `${survey(projectId, surveyId)}/folders/new`
export const questionnaireIndex = (projectId) => `${project(projectId)}/questionnaires`
export const collaboratorIndex = (projectId) => `${project(projectId)}/collaborators`
export const activityIndex = (projectId) => `${project(projectId)}/activity`
export const questionnaire = (projectId, questionnaireId) => `${questionnaireIndex(projectId)}/${questionnaireId}`
export const editQuestionnaire = (projectId, questionnaireId) => `${questionnaire(projectId, questionnaireId)}/edit`
export const exportQuestionnaireZip = (projectId, questionnaireId) => `/api/v1${questionnaire(projectId, questionnaireId)}/export_zip`
export const channelNew = (providerType, providerIndex) => `/channels/new?providerType=${providerType}&providerIndex=${providerIndex}`
export const channels = '/channels'
export const channelShare = (id) => `${channels}/${id}/share`
export const channelPatterns = (id) => `${channels}/${id}/patterns`
export const channelSettings = (id) => `${channels}/${id}/settings`

export const showOrEditSurvey = (s) => {
  if (s.state == 'not_ready' || s.state == 'ready') {
    return surveyEdit(s.projectId, s.id)
  } else {
    return survey(s.projectId, s.id)
  }
}
