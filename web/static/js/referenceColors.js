// @flow
import range from 'lodash/range'

const total = 16

export function referenceColorClasses(totalNeeded: number) {
  return referenceColorClassesWithPrefix(totalNeeded, 'referenceColor')
}

export function referenceBackgroundColorClasses(totalNeeded: number) {
  return referenceColorClassesWithPrefix(totalNeeded, 'referenceBackgroundColor')
}

export function referenceStrokeColorClasses(totalNeeded: number) {
  if (totalNeeded == 1) {
    return ['singleReferenceStrokeColor']
  }

  return referenceColorClassesWithPrefix(totalNeeded, 'referenceStrokeColor')
}

export function referenceColorClassesWithPrefix(totalNeeded: number, prefix: string) {
  let nextColorIncrement = total / totalNeeded
  return range(0, totalNeeded).map((i) => {
    return prefix + ((i * nextColorIncrement) % 16)
  })
}
