/// <reference types="Cypress" />

describe('survey', () => {
	it('starts a survey', () => {
		cy.log_into_instedd(Cypress.env('email'), Cypress.env('password'), Cypress.env('guisso_host'))
		cy.visit(Cypress.env('host')+Cypress.env('project_id'))
		cy.visit('https://surveda-stg.instedd.org/projects/322/surveys/3055')
		

		cy
		.request('https://surveda-stg.instedd.org/api/v1/projects/322/surveys/3055/respondents')
		.then((response) => {
			expect(response.body.data.respondents[0]).to.have.property('disposition', 'rejected')
		})


		cy.visit('https://surveda-stg.instedd.org/projects/322/questionnaires/')
		cy.wait(1000)
		cy.contains('Delete questionnaire').click({ force: true })


		cy.visit('https://surveda-stg.instedd.org/projects/322/surveys/')
		cy.get('.btn-large > .material-icons').click()
		cy.get(':nth-child(1) > .btn > .material-icons').click()
		cy.wait(1000)
		cy.get('#questionnaire > :nth-child(1) > :nth-child(2) > :nth-child(3) > .waves-effect').click()
		cy.get('.title-options > .dropdown-button > :nth-child(1)').click()
		cy.contains('Import questionnaire').click()
		const questionnaire_1 = '2118.zip';
		cy.get('input[type="file"]').attachFile(questionnaire_1);
		cy.go('back')

		//choose questionnaire. It should not be harcoded.
		cy.contains('Cipoletti 1')
			.then(($el) => {
				cy.contains($el.text()).click()
			}).click()

		//mode
		cy.contains('Select mode').click()
		cy.wait(1000)
		cy.get('.card-action > .row > :nth-child(1) > .select-wrapper > input.select-dropdown')
			.click({ force: true })
		cy.contains('SMS').click({ force: true })


		//upload sample
		cy.contains('Upload your respondents list').click()
		const sample_file = 'respondents_sample.csv';
		cy.get('input[type="file"]').attachFile(sample_file);

		cy.wait(1000)
		cy.get('.row > :nth-child(1) > .col > .select-wrapper > input.select-dropdown')
			.click()
		cy.wait(1000)
		cy.contains('simulator_1 - mmuller@manas.com.ar (staging)').click()
		cy.get('#input_4').select('simulator_1 - mmuller@manas.com.ar (staging)', { force: true })

		//schedule
		cy.get(':nth-child(3) > :nth-child(2) > .select-wrapper > input.select-dropdown')
			.click()
		//cy.wait(2000)
		cy.get('select').last().select('23:00:00', { force: true })
		cy.get(':nth-child(2) > .btn-floating').click()
		cy.get(':nth-child(3) > .btn-floating').click()
		cy.get(':nth-child(4) > .btn-floating').click()
		cy.get(':nth-child(5) > .btn-floating').click()
		cy.get(':nth-child(6) > .btn-floating').click()

		//quotas
		cy.get('.quotas > :nth-child(1) > label').click()
		cy.get(':nth-child(1) > .col > .right > label').click()
		cy.contains('Done').click()
		cy.get('#cutoff > :nth-child(1) > :nth-child(4) > .col > div > input')
			.clear()
			.type('10')

		//launch
		cy.get('.btn-floating > .material-icons').click()
	})
})