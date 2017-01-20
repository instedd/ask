import React, { PropTypes, Component } from 'react'
import { bindActionCreators } from 'redux'
import { connect } from 'react-redux'
import Dropzone from 'react-dropzone'
import { Input } from 'react-materialize'
import { ConfirmationModal, Card } from '../ui'
import * as actions from '../../actions/respondentGroups'
import values from 'lodash/values'
import uniq from 'lodash/uniq'
import flatMap from 'lodash/flatMap'

class SurveyWizardRespondentsStep extends Component {
  static propTypes = {
    survey: PropTypes.object,
    respondentGroups: PropTypes.object.isRequired,
    invalidRespondents: PropTypes.object,
    channels: PropTypes.object,
    actions: PropTypes.object.isRequired,
    readOnly: PropTypes.bool.isRequired
  }

  handleSubmit(files) {
    const { survey, actions } = this.props
    actions.uploadRespondentGroup(survey.projectId, survey.id, files)
  }

  removeRespondents(event, groupId) {
    const { survey, actions } = this.props
    actions.removeRespondentGroup(survey.projectId, survey.id, groupId)
  }

  clearInvalids(e) {
    e.preventDefault()

    this.props.actions.clearInvalids()
  }

  invalidRespondentsContent(data) {
    if (!data) return null

    const invalidEntriesText = data.invalidEntries.length === 1 ? 'An invalid entry was found at line ' : 'Invalid entries were found at lines '
    const lineNumbers = data.invalidEntries.slice(0, 3).map((entry) => entry.line_number)
    const extraLinesCount = data.invalidEntries.length - lineNumbers.length
    const lineNumbersText = lineNumbers.join(', ') + (extraLinesCount > 0 ? ' and ' + String(extraLinesCount) + ' more.' : '')
    return (
      <Card>
        <div className='card-content card-error'>
          <div><b>Errors found at '{data.filename}', file was not imported</b></div>
          <div>{invalidEntriesText} {lineNumbersText}</div>
          <div>Please fix those errors and upload again.</div>
        </div>
        <div className='card-action right-align'>
          <a className='blue-text' href='#' onClick={e => this.clearInvalids(e)}>
            UNDERSTOOD
          </a>
        </div>
      </Card>
    )
  }

  channelChange(e, group, type, allChannels) {
    e.preventDefault()

    let currentChannels = group.channels || []
    currentChannels = currentChannels.filter(id => allChannels[id].type != type)
    if (e.target.value != '') {
      currentChannels.push(e.target.value)
    }
    currentChannels = currentChannels.map(x => parseInt(x))

    const { actions, survey } = this.props
    actions.selectChannels(survey.projectId, survey.id, group.id, currentChannels)
  }

  renderGroup(group, channels, allModes, readOnly) {
    let removeRespondents = null
    if (!readOnly) {
      removeRespondents = <ConfirmationModal showLink
        modalId={`removeRespondents${group.id}`} linkText='REMOVE RESPONDENTS'
        modalText="Are you sure you want to delete the respondents list? If you confirm, we won't be able to recover it. You will have to upload a new one."
        header='Please confirm that you want to delete the respondents list'
        confirmationText='DELETE THE RESPONDENTS LIST'
        style={{maxWidth: '600px'}} showCancel
        onConfirm={e => this.removeRespondents(e, group.id)} />
    }

    return (
      <RespondentsList key={group.id} group={group} remove={removeRespondents} modes={allModes}
        channels={channels} readOnly={readOnly}
        onChannelChange={(e, type, allChannels) => this.channelChange(e, group, type, allChannels)}
        >
        {group.sample.map((respondent, index) =>
          <PhoneNumberRow id={respondent} phoneNumber={respondent} key={index} />
        )}
      </RespondentsList>
    )
  }

  render() {
    let { survey, channels, respondentGroups, invalidRespondents, readOnly } = this.props
    let invalidRespondentsCard = this.invalidRespondentsContent(invalidRespondents)
    if (!survey || !channels || Object.keys(channels).length == 0) {
      return <div>Loading...</div>
    }

    const mode = survey.mode || []
    const allModes = uniq(flatMap(mode))

    let respondentsDropzone = null
    if (!readOnly) {
      respondentsDropzone = (
        <RespondentsDropzone survey={survey} onDrop={file => this.handleSubmit(file)} onDropRejected={() => $('#invalidTypeFile').modal('open')} />
      )
    }

    return (
      <RespondentsContainer>
        {Object.keys(respondentGroups).map(groupId => this.renderGroup(respondentGroups[groupId], channels, allModes, readOnly))}

        <ConfirmationModal modalId='invalidTypeFile' modalText='The system only accepts CSV files' header='Invalid file type' confirmationText='accept' onConfirm={(event) => event.preventDefault()} style={{maxWidth: '600px'}} />
        {invalidRespondentsCard || respondentsDropzone}
      </RespondentsContainer>
    )
  }
}

const RespondentsDropzone = ({ survey, onDrop, onDropRejected }) => {
  return (
    <Dropzone className='dropfile' activeClassName='active' multiple={false} onDrop={onDrop} accept='.csv' onDropRejected={onDropRejected} >
      <div className='drop-icon' />
      <div className='drop-text csv' />
    </Dropzone>
  )
}

RespondentsDropzone.propTypes = {
  survey: PropTypes.object,
  onDrop: PropTypes.func.isRequired,
  onDropRejected: PropTypes.func.isRequired
}

const newChannelComponent = (type, allChannels, currentChannels, onChange, readOnly) => {
  const currentChannel = currentChannels.find(id => allChannels[id].type == type)

  let label
  if (type == 'sms') {
    label = 'SMS'
  } else {
    label = 'Phone'
  }
  label += ' channel'

  let channels = values(allChannels)
  channels = channels.filter(c => c.type == type)

  return (
    <div className='row' key={type}>
      <div className='input-field col s12'>
        <Input s={12} type='select' label={label}
          value={currentChannel || ''}
          onChange={e => onChange(e, type, allChannels)}
          disabled={readOnly}>
          <option value=''>
            Select a channel...
          </option>
          { channels.map((channel) =>
            <option key={channel.id} value={channel.id}>
              {channel.name}
            </option>
              )}
        </Input>
      </div>
    </div>
  )
}

const RespondentsList = ({ group, remove, channels, modes, onChannelChange, readOnly, children }) => {
  let footer = null
  if (remove) {
    footer = (
      <div className='card-action'>
        {remove}
      </div>
    )
  }

  let currentChannels = group.channels || []
  let channelsComponent = []
  for (const targetMode of modes) {
    channelsComponent.push(newChannelComponent(targetMode, channels, currentChannels, onChannelChange, readOnly))
  }

  return (
    <Card>
      <div className='card-content'>
        <div className='row'>
          <div className='col s6'>
            <table className='ncdtable'>
              <thead>
                <tr>
                  <th>{group.name} ({group.respondentsCount} contacts)</th>
                </tr>
              </thead>
              <tbody>
                {children}
              </tbody>
            </table>
          </div>
          <div className='col s6'>
            <table className='ncdtable'>
              <thead>
                <tr>
                  <th>Channels</th>
                </tr>
              </thead>
              <tbody>
                <tr>
                  <td>{channelsComponent}</td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>
      {footer}
    </Card>
  )
}

RespondentsList.propTypes = {
  group: PropTypes.object,
  modes: PropTypes.any,
  readOnly: PropTypes.bool,
  remove: PropTypes.node,
  channels: PropTypes.any,
  onChannelChange: PropTypes.func,
  children: PropTypes.node
}

const PhoneNumberRow = ({ id, phoneNumber }) => {
  return (
    <tr key={id}>
      <td>
        {phoneNumber}
      </td>
    </tr>
  )
}

PhoneNumberRow.propTypes = {
  id: PropTypes.string,
  phoneNumber: PropTypes.string
}

const RespondentsContainer = ({ children }) => {
  return (
    <div>
      <div className='row'>
        <div className='col s12'>
          <h4>Upload your respondents list</h4>
          <p className='flow-text'>
            Upload a CSV file like
            <a href='#' onClick={(e) => { e.preventDefault(); window.open('/files/phone_numbers_example.csv') }} download='phone_numbers_example.csv'> this one </a>
            with your respondents. You can define how many of these respondents need to successfully answer the survey by setting up cutoff rules.
          </p>
        </div>
      </div>
      <div className='row'>
        <div className='col s12'>
          {children}
        </div>
      </div>
    </div>
  )
}

RespondentsContainer.propTypes = {
  children: PropTypes.node
}

const mapDispatchToProps = (dispatch) => ({
  actions: bindActionCreators(actions, dispatch)
})

export default connect(null, mapDispatchToProps)(SurveyWizardRespondentsStep)
