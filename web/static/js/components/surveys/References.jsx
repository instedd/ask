import React, { Component } from 'react'

export default class References extends Component {
  render() {
    const {data} = this.props

    return (
      <div className="references">
        {
          data.map((reference, index) => {
            return (
              <div key={index} className="reference"><div style={reference.color?{background:reference.color}:null} className={`circle ${reference.className || ""}`}/>{reference.label}</div>
            )
          })
        }
      </div>
    )
  }
}
