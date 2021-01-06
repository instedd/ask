/// <reference types="Cypress" />

describe('surveys', () => {
  beforeEach(() => {
    cy.loginGuisso(Cypress.env('email'), Cypress.env('password'))

    // Create "Cipoletti 1" questionnaire
    const projectId = Cypress.env('project_id')
    cy.deleteProjectQuestionnaires(projectId)
    cy.visit(`/projects/${projectId}/questionnaires`)
    cy.clickMainAction('Add questionnaire')
    cy.waitForUrl(`/projects/:projectId/questionnaires/:questionnaireId/edit`).then(r => {
      const { questionnaireId } = r
      cy.clickTitleMenu()
      cy.contains('Import questionnaire').click()
      cy.get('input[type="file"]').attachFile('2118.zip');
    })
  })

  it('can be created with existing questionnaire', () => {
    const projectId = Cypress.env('project_id')
    const smsChannelId = Cypress.env('sms_channel_id')

    cy.visit(`/projects/${projectId}/surveys`)
    cy.clickMainAction('Add')
    cy.clickMainActionOption('Survey')

    cy.waitForUrl(`/projects/:projectId/surveys/:surveyId/edit`).then(r => {
      const { surveyId } = r

      // Set up questionnaire
      cy.contains('Select a questionnaire').click()
      cy.get("#questionnaire").within(() => {
        cy.contains('Cipoletti 1').click()
      })

      // Set up mode
      cy.contains('Select mode').click()
      cy.get("#channels").within(() => {
        cy.get('.card-action > .row > :nth-child(1) > .select-wrapper > input.select-dropdown').click({ force: true })
        cy.contains('SMS').click({ force: true })
      })

      // Upload respondents
      cy.contains('Upload your respondents list').click()
      cy.get("#respondents").within(() => {
        cy.get('input[type="file"]').attachFile('respondents_sample.csv')
        cy.get('input.select-dropdown + * + select').select(smsChannelId, { force: true })
      })

      // Set up schedule
      cy.contains('Setup a schedule').click()
      cy.get("#schedule").within(() => {
        cy.get(':nth-child(3) > :nth-child(2) > .select-wrapper > input.select-dropdown')
          .click()
        cy.get('select').last().select('23:00:00', { force: true })
        cy.get(':nth-child(2) > .btn-floating').click()
        cy.get(':nth-child(3) > .btn-floating').click()
        cy.get(':nth-child(4) > .btn-floating').click()
        cy.get(':nth-child(5) > .btn-floating').click()
        cy.get(':nth-child(6) > .btn-floating').click()
      })

      // Define quotas
      cy.contains('Setup cutoff rules').click()
      cy.get("#cutoff").within(() => {
        cy.get('.quotas > :nth-child(1) > label').click()
        cy.get(':nth-child(1) > .col > .right > label').click()
        cy.contains('Done').click()
        cy.get(':nth-child(1) > :nth-child(4) > .col > div > input')
          .clear()
          .type('10')
      })

      // Launch survey
      cy.clickMainAction('Launch survey')
    })
  })

  it('verifies valid state and disposition combinations', () => {
    const projectId = Cypress.env('project_id')
    cy.setUpSurvey('respondents_sample.csv').then((value) => {
      cy.wait(3000)
      cy.waitUntilStale(projectId, value, 10).then(() => {
        cy.surveyRespondents(projectId, value).then(respondents => {
          const invalidRespondents = respondents.filter(r => !validRespondentStateDisposition(r))

          cy.log(JSON.stringify(invalidRespondents))
        })
      })
    })
  })
})
