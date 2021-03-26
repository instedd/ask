import React, { PureComponent, PropTypes } from 'react'
import { translate } from 'react-i18next'
import { connect } from 'react-redux'
import { formatTimezone } from '../timezones/util'
import { Tooltip } from '../ui'
import { fetchTimezones } from '../../actions/timezones'
import classNames from 'classnames/bind'
import DownChannelsStatus from '../channels/DownChannelsStatus'
import dateformat from 'dateformat'
import map from 'lodash/map'
import min from 'lodash/min'
import i18n from '../../i18next'

class SurveyStatus extends PureComponent {
  static propTypes = {
    t: PropTypes.func,
    dispatch: PropTypes.func.isRequired,
    survey: PropTypes.object.isRequired,
    short: PropTypes.bool,
    timezones: PropTypes.object,
    language: PropTypes.string
  }

  componentDidMount() {
    const { dispatch } = this.props
    dispatch(fetchTimezones())
  }

  formatDate(date, timezone) {
    const { timezones, language } = this.props
    if (!timezones.items) return null
    const options = {
      timeZone: timezones.items[timezone],
      year: 'numeric',
      month: 'short',
      day: 'numeric',
      hour12: true,
      hour: 'numeric'
    }
    let dateString = date.toLocaleDateString(language, options).replace(/[,]/g, '')
    if (language == 'es') dateString = dateString.replace(/a\..m\./, 'AM').replace(/p\..m\./, 'PM')
    return `${dateString} ${formatTimezone(timezone)}`
  }

  nextCallDescription(survey, date) {
    const dateString = this.formatDate(date, survey.schedule.timezone)
    return this.props.t('Scheduled for {{dateString}}', {dateString})
  }

  surveyRanDescription(survey) {
    const { t } = this.props
    const formatDate = dateStr => dateformat(dateStr, 'yyyy-mm-dd')
    let startDate = formatDate(survey.startedAt)
    let endDate = formatDate(survey.endedAt)
    if (startDate === endDate) {
      return t('Ran only on {{startDate}}', { startDate })
    }
    return t('Ran from {{startDate}} to {{endDate}}', { startDate, endDate })
  }

  startedOnMessage() {
    const { survey, t } = this.props
    if (!survey.firstWindowStartedAt) return (t('Didn\'t start yet'))
    return t('Started on {{firstWindowStartedAt}}', {firstWindowStartedAt: this.formatDate(new Date(survey.firstWindowStartedAt), survey.schedule.timezone)})
  }

  endsOnMessage() {
    const { survey, t } = this.props
    const { lastWindowEndsAt } = survey
    if (!lastWindowEndsAt) return null
    return t('and will be canceled on {{lastWindowEndsAt}}', {lastWindowEndsAt: this.formatDate(new Date(survey.lastWindowEndsAt), survey.schedule.timezone)})
  }

  render() {
    const { survey, t, timezones, short } = this.props

    if (!survey) {
      return <p>{t('Loading...')}</p>
    }

    let icon = null
    let color = 'black-text'
    let text = null
    let tooltip = null
    let scheduleClarificationMessage = null

    switch (survey.state) {
      case 'not_ready':
        icon = 'mode_edit'
        text = t('Editing', { context: 'survey' })
        break

      case 'ready':
        icon = 'play_circle_outline'
        text = t('Ready to launch', { context: 'survey' })
        break

      case 'running':
        const endsOnMessage = this.endsOnMessage()
        scheduleClarificationMessage = `${this.startedOnMessage()}${endsOnMessage ? ` ${endsOnMessage}` : ''}`
        if (survey.downChannels.length > 0) {
          icon = 'cancel'
          const timestamp = min(map(survey.downChannels, (channel) => channel.timestamp))
          text = <DownChannelsStatus channels={survey.downChannels} timestamp={timestamp} />
          color = 'text-error'
          break
        } else {
          if (survey.nextScheduleTime) {
            if (timezones && timezones.items) {
              icon = 'access_time'
              const date = new Date(survey.nextScheduleTime)
              text = this.nextCallDescription(survey, date)
            }
          } else {
            icon = 'play_arrow'
            if (survey.firstWindowStartedAt) {
              text = short
              ? this.startedOnMessage()
              // On the survey overview, the "started on" message is included in the
              // scheduleClarification message, above the main message.
              : t('Running')
            } else {
              // When the survey will start immediately (there will be no distance between
              // started_at and first_window_started_at) there is a little time window while
              // the survey isn't active only because its first survey_poll didn't occur yet.
              // During this time window we tell the user that the survey is starting.
              text = t('Starting')
            }
          }
          color = 'green-text'
          break
        }

      case 'terminated':
        let status = state => t(`${state}${description}`, { context: 'survey' })
        const surveyRanDescription = this.surveyRanDescription(survey)
        let description = short
          ? `. ${surveyRanDescription}.`
          // Don't include this description on the survey overview message.
          // The same information is in the schedule clarification message.
          : ''
        scheduleClarificationMessage = surveyRanDescription
        switch (survey.exitCode) {
          case 0:
            icon = 'done'
            text = status('Completed')
            break

          case 1:
            icon = 'error'
            text = status('Cancelled')
            tooltip = survey.exitMessage
            break

          default:
            icon = 'error'
            color = 'text-error'
            text = status('Failed')
            tooltip = survey.exitMessage
            break
        }
        break
      case 'cancelling':
        switch (survey.exitCode) {
          case 1:
            icon = 'error'
            text = t('Cancelling', { context: 'survey' })
            tooltip = survey.exitMessage
            break

          default:
            icon = 'error'
            color = 'text-error'
            text = t('Failed', { context: 'survey' })
            tooltip = survey.exitMessage
            break
        }
        break

      default:
        icon = 'warning'
        color = 'text-error'
        text = t('Unknown', { context: 'survey' })
    }

    let component = (
      <span>
        <i className='material-icons survey-status'>{icon}</i>
        { text }
      </span>
    )

    if (tooltip) {
      component = (
        <Tooltip text={tooltip} position='top'>
          {component}
        </Tooltip>
      )
    }

    const scheduleClarification = scheduleClarificationMessage && !short &&
      (
      <span>
        <i className='material-icons survey-status'>event</i>
        { scheduleClarificationMessage }
      </span>
    )

    return (
      <div>
        <p>
          {scheduleClarification}
        </p>
        <p className={classNames(color, 'truncate', 'survey-status-container')}>
          {component}
        </p>
      </div>
    )
  }
}

const mapStateToProps = (state) => {
  return {
    timezones: state.timezones,
    language: i18n.language
  }
}

export default translate()(connect(mapStateToProps)(SurveyStatus))
