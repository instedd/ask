// @flow
import React, { Component } from 'react'
import { bindActionCreators } from 'redux'
import { connect } from 'react-redux'
import * as actions from '../../actions/respondents'
import * as surveyActions from '../../actions/survey'
import * as projectActions from '../../actions/project'
import * as questionnairesActions from '../../actions/questionnaires'
import values from 'lodash/values'
import { CardTable, UntitledIfEmpty, Modal, SortableHeader, Tooltip, PagingFooter } from '../ui'
import RespondentRow from './RespondentRow'
import * as routes from '../../routes'
import { modeLabel } from '../../questionnaire.mode'
import find from 'lodash/find'
import flatten from 'lodash/flatten'
import { translate } from 'react-i18next'
import classNames from 'classnames/bind'

type Props = {
  t: Function,
  projectId: number,
  surveyId: number,
  survey: Survey,
  project: Project,
  questionnaires: {[id: any]: Questionnaire},
  respondents: {[id: any]: Respondent},
  order: any[],
  userLevel: string,
  pageSize: number,
  pageNumber: number,
  totalCount: number,
  sortBy: any,
  sortAsc: any,
  startIndex: number,
  endIndex: number,
  surveyActions: any,
  projectActions: any,
  questionnairesActions: any,
  actions: any
};

type State = {
  csvType: string
};

class RespondentIndex extends Component<Props, State> {
  toggleResultsLink: Function
  toggleIncentivesLink: Function
  toggleInteractionsLink: Function
  toggleDispositionHistoryLink: Function
  refreshResultsLink: Function
  refreshIncentivesLink: Function
  refreshInteractionsLink: Function
  refreshDispositionHistoryLink: Function

  constructor(props) {
    super(props)
    this.state = {csvType: ''}
    this.toggleResultsLink = this.toggleResultsLink.bind(this)
    this.toggleIncentivesLink = this.toggleIncentivesLink.bind(this)
    this.toggleInteractionsLink = this.toggleInteractionsLink.bind(this)
    this.toggleDispositionHistoryLink = this.toggleDispositionHistoryLink.bind(this)
    this.refreshResultsLink = this.refreshResultsLink.bind(this)
    this.refreshIncentivesLink = this.refreshIncentivesLink.bind(this)
    this.refreshInteractionsLink = this.refreshInteractionsLink.bind(this)
    this.refreshDispositionHistoryLink = this.refreshDispositionHistoryLink.bind(this)
  }

  componentDidMount() {
    const { projectId, surveyId, pageSize } = this.props
    if (projectId && surveyId) {
      this.props.projectActions.fetchProject(projectId)
      this.props.surveyActions.fetchSurvey(projectId, surveyId)
      this.props.questionnairesActions.fetchQuestionnaires(projectId)
      this.props.actions.fetchRespondents(projectId, surveyId, pageSize, 1)
    }
  }

  nextPage() {
    const { projectId, surveyId, pageNumber, pageSize } = this.props
    this.props.actions.fetchRespondents(projectId, surveyId, pageSize, pageNumber + 1)
  }

  previousPage() {
    const { projectId, surveyId, pageNumber, pageSize } = this.props
    this.props.actions.fetchRespondents(projectId, surveyId, pageSize, pageNumber - 1)
  }

  downloadCSV() {
    const { projectId, surveyId } = this.props
    window.location = routes.respondentsResultsCSV(projectId, surveyId)
  }

  downloadDispositionHistoryCSV() {
    const { projectId, surveyId } = this.props
    window.location = routes.respondentsDispositionHistoryCSV(projectId, surveyId)
  }

  downloadIncentivesCSV() {
    const { projectId, surveyId } = this.props
    window.location = routes.respondentsIncentivesCSV(projectId, surveyId)
  }

  downloadInteractionsCSV() {
    const { projectId, surveyId } = this.props
    window.location = routes.respondentsInteractionsCSV(projectId, surveyId)
  }

  sortBy(name) {
    const { projectId, surveyId } = this.props
    this.props.actions.sortRespondentsBy(projectId, surveyId, name)
  }

  getModes(surveyModes) {
    return [...new Set(flatten(surveyModes))]
  }

  getModeAttempts() {
    const {survey, sortBy, sortAsc, t} = this.props
    let modes = this.getModes(survey.mode)
    let attemptsHeader = modes.map(function(mode) {
      const capitalize = str => str.charAt(0).toUpperCase() + str.slice(1)
      let modeTitle = capitalize(mode) + ' ' + 'Attempts'
      return <SortableHeader className='thNumber' key={mode} text={t(modeTitle)} property='stats' sortBy={sortBy} sortAsc={sortAsc} onClick={name => this.sortBy(name)} />
    }
    )
    return attemptsHeader
  }

  resultsAccessLink() {
    const {survey} = this.props
    return find(survey.links, (link) => link.name == `survey/${survey.id}/results`)
  }

  incentivesAccessLink() {
    const {survey} = this.props
    return find(survey.links, (link) => link.name == `survey/${survey.id}/incentives`)
  }

  interactionsAccessLink() {
    const {survey} = this.props
    return find(survey.links, (link) => link.name == `survey/${survey.id}/interactions`)
  }

  dispositionHistoryAccessLink() {
    const {survey} = this.props
    return find(survey.links, (link) => link.name == `survey/${survey.id}/disposition_history`)
  }

  toggleResultsLink(link) {
    const { projectId, surveyId, surveyActions } = this.props
    if (link) {
      surveyActions.deleteResultsLink(projectId, surveyId, link)
    } else {
      surveyActions.createResultsLink(projectId, surveyId)
    }
  }

  toggleIncentivesLink(link) {
    const { projectId, surveyId, surveyActions } = this.props
    if (link) {
      surveyActions.deleteIncentivesLink(projectId, surveyId, link)
    } else {
      surveyActions.createIncentivesLink(projectId, surveyId)
    }
  }

  toggleInteractionsLink(link) {
    const { projectId, surveyId, surveyActions } = this.props
    if (link) {
      surveyActions.deleteInteractionsLink(projectId, surveyId, link)
    } else {
      surveyActions.createInteractionsLink(projectId, surveyId)
    }
  }

  toggleDispositionHistoryLink(link) {
    const { projectId, surveyId, surveyActions } = this.props
    if (link) {
      surveyActions.deleteDispositionHistoryLink(projectId, surveyId, link)
    } else {
      surveyActions.createDispositionHistoryLink(projectId, surveyId)
    }
  }

  refreshResultsLink(link) {
    const { projectId, surveyId, surveyActions } = this.props
    surveyActions.refreshResultsLink(projectId, surveyId, link)
  }

  refreshIncentivesLink(link) {
    const { projectId, surveyId, surveyActions } = this.props
    surveyActions.refreshIncentivesLink(projectId, surveyId, link)
  }

  refreshInteractionsLink(link) {
    const { projectId, surveyId, surveyActions } = this.props
    surveyActions.refreshInteractionsLink(projectId, surveyId, link)
  }

  refreshDispositionHistoryLink(link) {
    const { projectId, surveyId, surveyActions } = this.props
    surveyActions.refreshDispositionHistoryLink(projectId, surveyId, link)
  }

  copyLink(link) {
    try {
      window.getSelection().selectAllChildren(link)
      document.execCommand('copy')
      window.getSelection().collapse(document.getElementsByTagName('body')[0], 0)

      window.Materialize.toast('Copied!', 3000)
    } catch (err) {
      window.Materialize.toast('Oops, unable to copy!', 3000)
    }
  }

  downloadLink(link, onChange, refresh, name) {
    const { project, t } = this.props

    return <div className='access-link'>
      {
        !project.readOnly
        ? <div className='switch'>
          <label>
            <input type='checkbox' checked={link != null} onChange={() => onChange(link)} />
            <span className='lever' />
            <span className='label' >{t('Public link:')}</span>
          </label>
        </div>
        : ''
      }
      {
        link != null
        ? <div className='link truncate'>
          <span ref={name}>{link.url}</span>
          <div className='buttons'>
            {
              !project.readOnly
              ? <Tooltip text='Refresh'>
                <a className='btn-icon-grey' onClick={refresh}>
                  <i className='material-icons'>refresh</i>
                </a>
              </Tooltip>
              : ''
            }
            <Tooltip text='Copy to clipboard'>
              <a className='btn-icon-grey' onClick={() => this.copyLink(this.refs[name])}>
                <i className='material-icons'>content_copy</i>
              </a>
            </Tooltip>
          </div>
        </div>
        : ''
      }
    </div>
  }

  responsesByField(respondents) {
    let responsesByField = {}
    for (let respondentId in respondents) {
      if (respondents.hasOwnProperty(respondentId)) {
        const responses = respondents[respondentId].responses
        for (let responseField in responses) {
          if (responses.hasOwnProperty(responseField)) {
            if (!responsesByField[responseField]) {
              responsesByField[responseField] = []
            }
            responsesByField[responseField].push(responses[responseField])
          }
        }
      }
    }
    return responsesByField
  }

  numericFields(respondents) {
    let responsesByField = this.responsesByField(respondents)
    let numericFields = []
    for (let responseField in responsesByField) {
      if (responsesByField.hasOwnProperty(responseField)) {
        if (responsesByField[responseField].every(response => !isNaN(response))) {
          numericFields.push(responseField)
        }
      }
    }
    return numericFields
  }

  fieldIsNumeric(numericFields, filterField) {
    return numericFields.some(field => field == filterField)
  }

  render() {
    const { survey, questionnaires, totalCount, order, sortBy, sortAsc, userLevel, t } = this.props

    if (!this.props.respondents || !survey || !questionnaires || !this.props.project) {
      return <div>{t('Loading...')}</div>
    }

    const hasComparisons = survey.comparisons.length > 0

    /* jQuery extend clones respondents object, in order to build an easy to manage structure without
    modify state */

    const respondents = generateResponsesDictionaryFor($.extend(true, {}, this.props.respondents))
    let numericFields = this.numericFields(respondents)

    const respondentsList: Respondent[] = values(respondents)

    function generateResponsesDictionaryFor(rs) {
      Object.keys(rs).forEach((respondentId, _) => {
        rs[respondentId].responses = responsesDictionaryFrom(rs[respondentId].responses)
      })
      return rs
    }

    function responsesDictionaryFrom(responseArray) {
      const res = {}
      for (const key in responseArray) {
        res[responseArray[key].name] = responseArray[key].value
      }
      return res
    }

    function allFieldNames(rs) {
      let fieldNames = Object.keys(rs).map((key) => (rs[key].responses))
      fieldNames = fieldNames.map((response) => Object.keys(response))
      fieldNames = [].concat.apply([], fieldNames)
      // Don't show fields for empty variable names
      fieldNames = fieldNames.filter(x => x.trim().length > 0)
      return fieldNames
    }

    function hasResponded(rs, respondentId, fieldName) {
      return Object.keys(rs[respondentId].responses).includes(fieldName)
    }

    function responseOf(rs, respondentId, fieldName) {
      return hasResponded(rs, respondentId, fieldName) ? rs[respondentId].responses[fieldName] : '-'
    }

    const { startIndex, endIndex } = this.props

    const title = t('{{count}} respondent', {count: totalCount})
    const footer = <PagingFooter
      {...{startIndex, endIndex, totalCount}}
      onPreviousPage={() => this.previousPage()}
      onNextPage={() => this.nextPage()} />

    const respondentsFieldName = allFieldNames(respondents)

    let colspan = respondentsFieldName.length + 3
    let variantHeader = null
    if (hasComparisons) {
      variantHeader = <th>{t('Variant')}</th>
      colspan += 1
    }

    let incentivesCsvLink = null
    if (userLevel == 'owner' || userLevel == 'admin') {
      incentivesCsvLink = (
        <li className='collection-item'>
          <a href='#' className='download' onClick={e => { e.preventDefault(); this.downloadIncentivesCSV() }}>
            <div>
              <i className='material-icons'>get_app</i>
            </div>
            <div>
              <p className='black-text'><b>{t('Incentives file')}</b></p>
              <p>{t('One line for each respondent that completed the survey, including the experiment version and the full phone number')}</p>
            </div>
          </a>
          {this.downloadLink(this.incentivesAccessLink(), this.toggleIncentivesLink, this.refreshIncentivesLink, 'incentivesLink')}
        </li>
      )
    }

    let interactionsCsvLink = null
    if (userLevel == 'owner' || userLevel == 'admin') {
      interactionsCsvLink = (
        <li className='collection-item'>
          <a href='#' className='download' onClick={e => { e.preventDefault(); this.downloadInteractionsCSV() }}>
            <div>
              <i className='material-icons'>get_app</i>
            </div>
            <div>
              <p className='black-text'><b>{t('Interactions')}</b></p>
              <p>{t('One line per respondent interaction, with a column describing the action type and data, including disposition and timestamp')}</p>
            </div>
          </a>
          {this.downloadLink(this.interactionsAccessLink(), this.toggleInteractionsLink, this.refreshInteractionsLink, 'interactionsLink')}
        </li>
      )
    }
    return (
      <div className='white'>
        <div dangerouslySetInnerHTML={{
          __html: '<style> body { overflow-y: auto !important; color: black}</style>' }} />
        <div className='fixed-action-btn horizontal right mtop'>
          <a className='btn-floating btn-large green' href='#' onClick={(e) => { e.preventDefault(); $('#downloadCSV').modal('open') }}>
            <i className='material-icons'>get_app</i>
          </a>
        </div>
        <Modal id='downloadCSV' confirmationText='Download CSV' card>
          <div className='card-title header'>
            <h5>{t('Download CSV')}</h5>
            <p>{t('Download survey respondents data as CSV')}</p>
          </div>
          <ul className='collection download-csv'>
            <li className='collection-item'>
              <a href='#' className='download' onClick={e => { e.preventDefault(); this.downloadCSV() }}>
                <div>
                  <i className='material-icons'>get_app</i>
                </div>
                <div>
                  <p className='black-text'><b>{t('Survey results')}</b></p>
                  <p>{t('One line per respondent, with a column for each variable in the questionnaire, including disposition and timestamp')}</p>
                </div>
              </a>
              {this.downloadLink(this.resultsAccessLink(), this.toggleResultsLink, this.refreshResultsLink, 'resultsLink')}
            </li>
            <li className='collection-item'>
              <a href='#' className='download' onClick={e => { e.preventDefault(); this.downloadDispositionHistoryCSV() }}>
                <div>
                  <i className='material-icons'>get_app</i>
                </div>
                <div>
                  <p className='black-text'><b>{t('Disposition History')}</b></p>
                  <p>{t('One line for each time the disposition of a respondent changed, including the timestamp')}</p>
                </div>
              </a>
              {this.downloadLink(this.dispositionHistoryAccessLink(), this.toggleDispositionHistoryLink, this.refreshDispositionHistoryLink, 'dispositionHistoryLink')}
            </li>
            {incentivesCsvLink}
            {interactionsCsvLink}
          </ul>
        </Modal>
        <div className='input-field'>
          <input type='search' className='search-input' />
          <i className='material-icons grey-text'>search</i>
          <span className='small-text-bellow'>Filter by properties using the following format <em>property:value[value,...].</em> <a href='#'>View advanced search syntax</a></span>
        </div>
        <CardTable title={title} footer={footer} tableScroll>
          <thead>
            <tr>
              <SortableHeader text={t('Respondent ID')} property='phoneNumber' sortBy={sortBy} sortAsc={sortAsc} onClick={name => this.sortBy(name)} />
              <th>{t('Disposition')}</th>
              <SortableHeader className='thDate' text={t('Date')} property='date' sortBy={sortBy} sortAsc={sortAsc} onClick={name => this.sortBy(name)} />
              {this.getModeAttempts()}
              {respondentsFieldName.map(field =>
                <th className={classNames({'thNumber': this.fieldIsNumeric(numericFields, field)})} key={field}>{field}</th>
              )}
              {variantHeader}
            </tr>
          </thead>
          <tbody>
            { order.map((respondentId, index) => {
              const respondent = respondentsList.find(r => r.id == respondentId)
              if (!respondent) return <tr key={-index} className='empty-row'><td colSpan={colspan} /></tr>

              let variantColumn = null
              if (hasComparisons) {
                let variantValue
                let questionnaire
                if (respondent.questionnaireId && respondent.mode && (questionnaire = questionnaires[respondent.questionnaireId])) {
                  const questionnaireName = <UntitledIfEmpty text={questionnaire.name} emptyText={t('Untitled questionnaire')} />
                  variantValue = <span>{questionnaireName} - {modeLabel(respondent.mode)}</span>
                } else {
                  variantValue = '-'
                }

                variantColumn = <td>{variantValue}</td>
              }

              const responses = respondentsFieldName.map((field) => {
                return {
                  name: field,
                  value: responseOf(respondents, respondent.id, field)
                }
              })
              return <RespondentRow
                cellClassNames={(fieldName) => classNames({
                  'tdNowrap': true,
                  'tdNumber': this.fieldIsNumeric(numericFields, fieldName)})}
                key={index}
                respondent={respondent}
                responses={responses}
                variantColumn={variantColumn}
                surveyModes={this.getModes(survey.mode)}
                />
            })}
          </tbody>
        </CardTable>
      </div>
    )
  }
}

const mapStateToProps = (state, ownProps) => {
  const pageNumber = state.respondents.page.number
  const pageSize = state.respondents.page.size
  const totalCount = state.respondents.page.totalCount
  const sortBy = state.respondents.sortBy
  const sortAsc = state.respondents.sortAsc
  const startIndex = (pageNumber - 1) * state.respondents.page.size + 1
  const endIndex = Math.min(startIndex + state.respondents.page.size - 1, totalCount)
  return {
    projectId: ownProps.params.projectId,
    surveyId: ownProps.params.surveyId,
    survey: state.survey.data,
    project: state.project.data,
    questionnaires: state.questionnaires.items,
    respondents: state.respondents.items,
    order: state.respondents.order,
    userLevel: state.project.data ? state.project.data.level : '',
    pageNumber,
    pageSize,
    startIndex,
    endIndex,
    totalCount,
    sortBy,
    sortAsc
  }
}

const mapDispatchToProps = (dispatch) => ({
  actions: bindActionCreators(actions, dispatch),
  surveyActions: bindActionCreators(surveyActions, dispatch),
  projectActions: bindActionCreators(projectActions, dispatch),
  questionnairesActions: bindActionCreators(questionnairesActions, dispatch)
})

export default translate()(connect(mapStateToProps, mapDispatchToProps)(RespondentIndex))
