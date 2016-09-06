import React from 'react'
import { Route, IndexRedirect } from 'react-router'
import App from './containers/App'
import Projects from './containers/Projects'
import CreateProject from './containers/CreateProject'
import EditProject from './containers/EditProject'
import EditSurvey from './containers/EditSurvey'
import Surveys from './containers/Surveys'
import Survey from './containers/Survey'
import SurveyQuestionnaireStep from './components/SurveyQuestionnaireStep'
import Questionnaires from './containers/Questionnaires'
import CreateQuestionnaire from './containers/CreateQuestionnaire'
import Channels from './containers/channels/Channels'
import EditQuestionnaire from './containers/EditQuestionnaire'
//import UserPage from './containers/UserPage'
//import RepoPage from './containers/RepoPage'

export default (
  <div>
    <Route path ="/" component={App}>
      <Route path ="/projects" component={Projects} />
      <Route path ="/projects/new" component={CreateProject} />
      <Route path ="/projects/:id/edit" component={EditProject} />
      <Route path ="/projects/:id">
        <IndexRedirect to="surveys"/>
      </Route>
      <Route path ="/projects/:projectId/surveys" component={Surveys} />
      <Route path ="/projects/:projectId/surveys/:id" component={Survey} />
      <Route path ="/projects/:projectId/surveys/:id/edit" component={EditSurvey} >
        <IndexRedirect to="questionnaire"/>
        <Route path ="questionnaire" component={SurveyQuestionnaireStep} />
      </Route>
      <Route path ="/projects/:projectId/questionnaires" component={Questionnaires} />
      <Route path ="/projects/:projectId/questionnaires/new" component={CreateQuestionnaire} />
      <Route path ="/projects/:projectId/questionnaires/:id">
        <IndexRedirect to="edit"/>
      </Route>
      <Route path ="/projects/:projectId/questionnaires/:id/edit" component={EditQuestionnaire} />
      <Route path="/channels" component={Channels} />
    </Route>
  </div>
)
