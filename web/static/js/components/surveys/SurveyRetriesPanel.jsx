import React, { Component, PropTypes } from 'react'
import { connect } from 'react-redux'
import * as actions from '../../actions/survey'
import { translate } from 'react-i18next'
import RetriesHistogram from './RetriesHistogram'

class SurveyRetriesPanel extends Component {
  static propTypes = {
    retriesHistograms: PropTypes.array,
    dispatch: PropTypes.func.isRequired,
    projectId: PropTypes.string.isRequired,
    surveyId: PropTypes.string.isRequired,
    t: PropTypes.func.isRequired,
    target: PropTypes.number.isRequired
  }

  componentWillMount() {
    const { dispatch, projectId, surveyId } = this.props
    dispatch(actions.fetchSurveyRetriesHistograms(projectId, surveyId))
  }

  typeForRetriesHistogram(type) {
    switch (type) {
      case 'ivr':
        return 'voice'
      case 'end':
        return 'discard'
    }
    return type
  }

  delayForRetriesHistogram(delay, isFirstAttempt) {
    // It doesn't feel right hardcoding 1 when the delay is 0
    // But we need this for when the delay is less than an hour
    // Otherwise, the hole graph crashes
    return isFirstAttempt ? delay : delay || 1
  }

  flowForRetriesHistogram(flow) {
    const cloned = [...flow]
    let offset = 0
    cloned.forEach(step => {
      offset += step.delay
      step.offset = offset
    })
    return cloned.map(({delay, type, label, offset}, idx) => ({
      delay: this.delayForRetriesHistogram(delay, idx == 0),
      type: this.typeForRetriesHistogram(type),
      label,
      offset
    }))
  }

  render() {
    const { retriesHistograms, target, t } = this.props

    const getHistogram = h => {
      const flow = this.flowForRetriesHistogram(h.flow)
      const histLength = flow.reduce((total, attempt) => total + attempt.delay, 1)
      const histActives = new Array(histLength)

      let i
      for (i = 0; i < histLength; i++) {
        histActives[i] = {value: 0}
      }
      h.actives.forEach(slot => {
        histActives[slot.hour].value = slot.respondents
      })

      return {
        actives: histActives,
        flow: flow,
        // It doesn't apply to the current iteration
        completes: histActives.map(() => false),
        // It doesn't apply to the current iteration
        timewindows: histActives.map(() => true)
      }
    }

    const getHistograms = () => {
      if (!retriesHistograms) return t('Loading...')
      return retriesHistograms.map(h => getHistogram(h)).map(h => <RetriesHistogram
        // Used in the y-axis height calculation
        quota={target}
        // Every attempt in the mode sequence, including the delay between them
        flow={h.flow}
        // Every set of active respondents grouped and ordered by hour
        actives={h.actives}
        // Every set of completed respondents grouped and ordered by hour
        completes={h.completes}
        // Every hour while the survey is active is flagged as true
        timewindows={h.timewindows}
        // Text about the current and next state of the survey regarding its schedule
        // It doesn't apply to the current iteration
        scheduleDescription=''
        // Graph references
        references={[
          {
            label: t('Trying'),
            className: 'trying'
          },
          {
            label: t('Stand by'),
            className: 'standby'
          }
        ]}
        />)
    }

    return (<div className='retries-histogram' style={{'marginTop': '20px'}}>
      <div className='header'>
        <div className='title'>{t('Retries histograms')}</div>
        <div className='description'>{t('Number of contacts in each stage of the retry schedule')}</div>
      </div>
      { getHistograms() }
    </div>)
  }
}

const mapStateToProps = (state, ownProps) => {
  const surveyRetriesHistograms = ownProps.surveyId == state.survey.data.id ? state.surveyRetriesHistograms.histograms : null

  return ({
    retriesHistograms: surveyRetriesHistograms
  })
}

export default translate()(connect(mapStateToProps)(SurveyRetriesPanel))
