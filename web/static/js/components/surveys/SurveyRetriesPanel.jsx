// @flow
import React, { Component, PropTypes } from 'react'
import { connect } from 'react-redux'
import { translate } from 'react-i18next'
import * as actions from '../../actions/survey'
import RetriesHistogram from './RetriesHistogram'

class SurveyRetriesPanel extends Component<any, State> {
  static propTypes = {
    retriesHistograms: PropTypes.array
  }

  componentWillMount() {
    const { dispatch, projectId, surveyId } = this.props
    console.log(`LAS PROPSSSS ${this.props}`)
    dispatch(actions.fetchSurveyRetriesHistograms(projectId, surveyId))
  }

  render() {
    const { t, retriesHistograms } = this.props

    const getHistogram = h => {
      const translateType = type => {
        switch (type) {
          case 'ivr':
            return 'voice'
          case 'end':
            return 'discard'
        }
        return type
      }
      const flow = h.flow.map(({delay, type, label}, idx) => ({delay: idx != 0 && delay == 0 ? 1 : delay, type: translateType(type), label}))
      let offset = 0
      flow.forEach(step => {
        offset += step.delay
        step.offset = offset
      })
      const histLength = flow.reduce((total, attempt) => total + (attempt.delay ? attempt.delay : 1), 0)

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
        references: [{label: 'Trying', className: 'trying'}, {label: 'Stand by', className: 'standby'}],
        quota: 100
      }
    }

    const getHistograms = () => {
      console.log(`retriesHistograms: ${retriesHistograms}`)
      if (!retriesHistograms) return null

      return retriesHistograms.map(h => getHistogram(h)).map(h => <RetriesHistogram quota={h.quota} flow={h.flow} actives={h.actives} completes={h.actives.map(() => false)} timewindows={h.actives.map(() => true)} scheduleDescription='' references={h.references} />)
    }

    return (
      <div className='retries-histogram' style={{'marginTop': '20px'}}>
        <div className='header'>
          <div className='title'>{t('Retries histograms')}</div>
          <div className='description'>{t('Number of contacts in each stage of the retry schedule')}</div>
        </div>
        { getHistograms() }
      </div>
    )
  }
}

const mapStateToProps = (state) => {
  const surveyRetriesHistograms = state.surveyRetriesHistograms.surveyId == state.survey.data.id ? state.surveyRetriesHistograms.histograms : null

  return ({
    projectId: state.project.data.id,
    project: state.project.data,
    surveyId: state.survey.data.id,
    survey: state.survey.data,
    retriesHistograms: surveyRetriesHistograms
  })
}

export default translate()(connect(mapStateToProps)(SurveyRetriesPanel))
