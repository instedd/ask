import * as actions from '../../actions/survey'
import { connect } from 'react-redux'
import React, { PropTypes, Component } from 'react'
import TimezoneDropdown from '../timezones/TimezoneDropdown'
import TimeDropdown from '../ui/TimeDropdown'
import SurveyWizardRetryAttempts from './SurveyWizardRetryAttempts'

class SurveyWizardScheduleStep extends Component {
  static propTypes = {
    survey: PropTypes.object.isRequired,
    dispatch: PropTypes.func.isRequired
  }

  updateFrom(event) {
    const { dispatch } = this.props
    dispatch(actions.setScheduleFrom(event.target.value))
  }

  updateTo(event) {
    const { dispatch } = this.props
    dispatch(actions.setScheduleTo(event.target.value))
  }

  updateTimezone(event) {
    const { dispatch } = this.props
    dispatch(actions.setTimezone(event.target.value))
  }

  toggleDay(day) {
    const { dispatch } = this.props
    dispatch(actions.toggleDay(day))
  }

  render() {
    const { survey } = this.props
    const days = ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat']

    // Survey might be loaded without details
    let defaultFrom = (survey && survey.scheduleStartTime) ? survey.scheduleStartTime : '09:00:00'
    let defaultTo = (survey && survey.scheduleEndTime) ? survey.scheduleEndTime : '18:00:00'

    if (!survey || !survey.scheduleDayOfWeek) {
      return <div>Loading...</div>
    }

    return (
      <div>
        <div className='row'>
          <div className='col s12'>
            <h4>Set up a schedule</h4>
            <p className='flow-text'>
              The schedule of your survey restricts the days and hours during which respondents will be contacted. You can also specify re-contact attempts intervals.
            </p>
          </div>
        </div>
        <div className='row'>
          {days.map((day) => (
            <div className='col' key={day}>
              <button type='button' className={`btn-floating btn-flat btn-large waves-effect waves-light ${survey.scheduleDayOfWeek[day] ? 'green white-text' : 'grey lighten-3 grey-text text-darken-1'}`} onClick={() =>
                this.toggleDay(day)
              }>
                {day}
              </button>
            </div>
          ))}
        </div>
        <div className='row'>
          <TimezoneDropdown selectedTz={survey && survey.timezone} onChange={e => this.updateTimezone(e)} />
        </div>
        <div className='row'>
          <TimeDropdown label='From' defaultValue={defaultFrom} onChange={e => this.updateFrom(e)} />
          <TimeDropdown label='To' defaultValue={defaultTo} onChange={e => this.updateTo(e)} />
        </div>
        <SurveyWizardRetryAttempts />
      </div>
    )
  }
}

const mapStateToProps = (state, ownProps) => ({
  timezones: state.timezones
})

export default connect(mapStateToProps)(SurveyWizardScheduleStep)
