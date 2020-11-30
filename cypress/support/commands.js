// ***********************************************
// This example commands.js shows you how to
// create various custom commands and overwrite
// existing commands.
//
// For more comprehensive examples of custom
// commands please read more here:
// https://on.cypress.io/custom-commands
// ***********************************************
//
//
// -- This is a parent command --
// Cypress.Commands.add("login", (email, password) => { ... })
//
//
// -- This is a child command --
// Cypress.Commands.add("drag", { prevSubject: 'element'}, (subject, options) => { ... })
//
//
// -- This is a dual command --
// Cypress.Commands.add("dismiss", { prevSubject: 'optional'}, (subject, options) => { ... })
//
//
// -- This will overwrite an existing command --
// Cypress.Commands.overwrite("visit", (originalFn, url, options) => { ... })

Cypress.Commands.add('log_into_instedd', (email, pwd, guisso_host) => {
  cy.visit(guisso_host)

  cy.get('.fieldset')
    .find('input[name="user[email]"]')
    .invoke('attr', 'value', email)
    .should('have.value', email)

  cy.get('.fieldset')
    .find('input[name="user[password]"]')
    .invoke('attr', 'value', pwd)
    .should('have.value', pwd)

  cy.contains('Log in').click()
})

import 'cypress-file-upload';
