// @flow
import React, { Component } from 'react'
import { bindActionCreators } from 'redux'
import { connect } from 'react-redux'
import * as actions from '../../actions/respondents'
import * as surveyActions from '../../actions/survey'
import * as projectActions from '../../actions/project'
import * as questionnairesActions from '../../actions/questionnaires'
import values from 'lodash/values'
import {
  CardTable,
  UntitledIfEmpty,
  Modal,
  SortableHeader,
  Tooltip,
  PagingFooter,
  MainAction,
  Action,
  Dropdown,
  DropdownItem
} from '../ui'
import RespondentRow from './RespondentRow'
import * as routes from '../../routes'
import { modeLabel } from '../../questionnaire.mode'
import find from 'lodash/find'
import flatten from 'lodash/flatten'
import { translate } from 'react-i18next'
import classNames from 'classnames/bind'
import RespondentsFilter from './RespondentsFilter'

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
  actions: any,
  router: Object,
  filter: string,
  q: string
}

type State = {
  csvType: string
}

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
    const {
      projectId,
      surveyId,
      projectActions,
      surveyActions,
      questionnairesActions,
      q
    } = this.props
    if (projectId && surveyId) {
      projectActions.fetchProject(projectId)
      surveyActions.fetchSurvey(projectId, surveyId)
      questionnairesActions.fetchQuestionnaires(projectId)
      this.fetchRespondents(1, q)
    }
  }

  fetchRespondents(pageNumber = 1, overrideFilter = null) {
    const {
      projectId,
      surveyId,
      pageSize,
      filter,
      sortBy,
      sortAsc
    } = this.props
    const _filter = overrideFilter == null ? filter : overrideFilter
    this.props.actions.fetchRespondents(
      projectId,
      surveyId,
      pageSize,
      pageNumber,
      _filter,
      sortBy,
      sortAsc
    )
  }

  nextPage() {
    const { pageNumber } = this.props
    this.fetchRespondents(pageNumber + 1)
  }

  previousPage() {
    const { pageNumber } = this.props
    this.fetchRespondents(pageNumber - 1)
  }

  downloadCSV(applyUserFilter = false) {
    const { projectId, surveyId, filter } = this.props
    const q = (applyUserFilter && filter) || null
    window.location = routes.respondentsResultsCSV(projectId, surveyId, q)
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

  getModeAttemptsHeaders() {
    const { survey, t } = this.props
    const renderHeader = (displayText, key) =>
      this.renderHeader({
        displayText: displayText,
        key: key,
        sortable: false,
        type: 'number'
      })
    return this.getModes(survey.mode).map(function(mode) {
      const capitalize = (str) => str.charAt(0).toUpperCase() + str.slice(1)
      return renderHeader(
        t('{{mode}} Attempts', { mode: capitalize(mode) }),
        mode
      )
    })
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

  downloadItem(id, itemType) {
    const { t, totalCount, filter } = this.props
    const titleDescription = item => (
      <div>
        <p className='black-text'><b>{item.title}</b></p>
        <p>{item.description}</p>
      </div>
    )

    const render = item =>
    (
      <li className='collection-item'>
        {
          itemType == 'file'
          ? (
            <a href='#' className='download' onClick={e => { e.preventDefault(); item.onDownload() }}>
              <div>
                <i className='material-icons'>get_app</i>
              </div>
              { titleDescription(item) }
            </a>
          )
          : <div className='link'>{titleDescription(item)}</div>
        }
        { itemType == 'link' ? item.downloadLink : null }
      </li>
    )

    switch (id) {
      case 'filtered-results':
        return render({
          title: t('Filtered survey results'),
          description: t(
            '{{totalCount}} respondents resulting of applying the current filter: {{filter}}',
            { totalCount, filter }
          ),
          downloadLink: null,
          onDownload: () => this.downloadCSV(true)
        })
      case 'results':
        return render({
          title: t('Survey results'),
          description: t('One line per respondent, with a column for each variable in the questionnaire, including disposition and timestamp'),
          downloadLink: this.downloadLink(this.resultsAccessLink(), this.toggleResultsLink, this.refreshResultsLink, 'resultsLink'),
          onDownload: () => this.downloadCSV()
        })
      case 'disposition-history':
        return render({
          title: t('Disposition History'),
          description: t('One line for each time the disposition of a respondent changed, including the timestamp'),
          downloadLink: this.downloadLink(this.dispositionHistoryAccessLink(), this.toggleDispositionHistoryLink, this.refreshDispositionHistoryLink, 'dispositionHistoryLink'),
          onDownload: () => this.downloadDispositionHistoryCSV()
        })
      case 'incentives':
        return render({
          title: t('Incentives file'),
          description: t('One line for each respondent that completed the survey, including the experiment version and the full phone number'),
          downloadLink: this.downloadLink(this.incentivesAccessLink(), this.toggleIncentivesLink, this.refreshIncentivesLink, 'incentivesLink'),
          onDownload: () => this.downloadIncentivesCSV()
        })
      case 'interactions':
        return render({
          title: t('Interactions'),
          description: t('One line per respondent interaction, with a column describing the action type and data, including disposition and timestamp'),
          downloadLink: this.downloadLink(this.interactionsAccessLink(), this.toggleInteractionsLink, this.refreshInteractionsLink, 'interactionsLink'),
          onDownload: () => this.downloadInteractionsCSV()
        })
    }
  }

  onFilterChange(value) {
    const { router, projectId, surveyId, actions } = this.props
    router.push(routes.surveyRespondents(projectId, surveyId, value))
    actions.updateRespondentsFilter(projectId, surveyId, value)
  }

  respondentsFilter() {
    const { q } = this.props
    return (
      <RespondentsFilter
        defaultValue={q}
        onChange={value => this.onFilterChange(value)}
      />
    )
  }

  downloadModal({ itemType }) {
    const { userLevel, t, filter } = this.props
    const ownerOrAdmin = userLevel == 'owner' || userLevel == 'admin'
    const [title, description] =
      itemType == 'file'
        ? [t('Download CSV'), t('Choose the data you want to download')]
        : [
          t('Public links'),
          t(
            'Choose the data you want to be able to access through a public link'
          )
        ]

    return (
      <Modal
        id={`downloadCSV-${itemType}`}
        confirmationText='Download CSV'
        card
      >
        <div className='card-title header'>
          <h5>{title}</h5>
          <p>{description}</p>
        </div>
        <ul className='collection download-csv'>
          {itemType == 'file' && filter
            ? this.downloadItem('filtered-results', itemType)
            : null}
          {this.downloadItem('results', itemType)}
          {this.downloadItem('disposition-history', itemType)}
          {ownerOrAdmin ? this.downloadItem('incentives', itemType) : null}
          {ownerOrAdmin ? this.downloadItem('interactions', itemType) : null}
        </ul>
      </Modal>
    )
  }

  renderHeader({displayText, key, sortable, type}) {
    const { sortBy, sortAsc } = this.props
    let className = classNames({
      'thNumber': type === 'number',
      'thDate': type === 'date'
    })

    if (sortable) {
      return <SortableHeader text={displayText} property={key} sortBy={sortBy}
        sortAsc={sortAsc} onClick={() => this.sortBy(key)} />
    } else {
      return <th className={className} key={key}>{displayText}</th>
    }
  }

  render() {
    const { project,
      survey,
      questionnaires,
      totalCount,
      order,
      t
    } = this.props
    const loading = (
      !project ||
      !survey ||
      !this.props.respondents ||
      !questionnaires
    )

    if (loading) {
      return <div>
        {t('Loading...')}
      </div>
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
      variantHeader = this.renderHeader({
        displayText: t('Variant'),
        key: 'variant',
        sortable: false,
        type: null
      })
      colspan += 1
    }
    const [fileId, linkId] = ['file', 'link']

    const titleWithColumnsMenu = <div className='respondent-index-table-title'>
      <div>
        {title}
      </div>
      <Dropdown className='options columns-menu' dataBelowOrigin={false}
        label={<i className='material-icons'>more_vert</i>}>
        <DropdownItem className='dots'>
          <i className='material-icons'>more_vert</i>
        </DropdownItem>
      </Dropdown>
    </div>

    return (
      <div className='white'>
        <div dangerouslySetInnerHTML={{
          __html: '<style> body { overflow-y: auto !important; color: black}</style>' }} />
        <MainAction text='Downloads' icon='get_app'>
          <Action text='Download CSVs' icon='insert_drive_file' onClick={() => $(`#downloadCSV-${fileId}`).modal('open')} />
          <Action text='Public links' icon='link' onClick={() => $(`#downloadCSV-${linkId}`).modal('open')} />
        </MainAction>
        { this.downloadModal({itemType: fileId}) }
        { this.downloadModal({itemType: linkId}) }
        { this.respondentsFilter() }
        <CardTable title={titleWithColumnsMenu} footer={footer} tableScroll>
          <thead>
            <tr>
              {
                this.renderHeader({
                  displayText: t('Respondent ID'),
                  key: 'phoneNumber',
                  sortable: true,
                  type: null
                })
              }
              {
                this.renderHeader({
                  displayText: t('Disposition'),
                  key: 'disposition',
                  sortable: false,
                  type: null
                })
              }
              {
                this.renderHeader({
                  displayText: t('Date'),
                  key: 'date',
                  sortable: true,
                  type: 'date'
                })
              }
              {
                this.getModeAttemptsHeaders()
              }
              {
                respondentsFieldName.map(field => (
                  this.renderHeader({
                    displayText: field,
                    key: field,
                    sortable: false,
                    type: this.fieldIsNumeric(numericFields, field) ? 'number' : null
                  })
                ))
              }
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
  const { project, survey, questionnaires, respondents } = state
  const { page, sortBy, sortAsc, order, filter, items } = respondents
  const { number: pageNumber, size: pageSize, totalCount } = page
  const { projectId, surveyId } = ownProps.params
  const startIndex = (pageNumber - 1) * pageSize + 1
  const endIndex = Math.min(startIndex + pageSize - 1, totalCount)

  return {
    projectId,
    surveyId,
    q: ownProps.location.query.q || '',
    survey: survey.data,
    project: project.data,
    questionnaires: questionnaires.items,
    respondents: items,
    order,
    userLevel: project.data ? project.data.level : '',
    pageNumber,
    pageSize,
    startIndex,
    endIndex,
    totalCount,
    sortBy,
    sortAsc,
    filter
  }
}

const mapDispatchToProps = (dispatch) => ({
  actions: bindActionCreators(actions, dispatch),
  surveyActions: bindActionCreators(surveyActions, dispatch),
  projectActions: bindActionCreators(projectActions, dispatch),
  questionnairesActions: bindActionCreators(questionnairesActions, dispatch)
})

export default translate()(
  connect(
    mapStateToProps,
    mapDispatchToProps
  )(RespondentIndex)
)
