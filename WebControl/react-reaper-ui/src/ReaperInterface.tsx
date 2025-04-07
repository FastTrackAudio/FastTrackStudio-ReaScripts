import React, { useState, useEffect } from "react"
import "./ReaperInterface.css"

// Declare the ReaperWRB global provided by REAPER's web interface
declare global {
  interface Window {
    ReaperWRB: any
  }
}

interface ReaperInterfaceProps {
  title: string
}

const ReaperInterface: React.FC<ReaperInterfaceProps> = ({ title }) => {
  const [tracks, setTracks] = useState<string[]>([])
  const [isConnected, setIsConnected] = useState<boolean>(false)

  useEffect(() => {
    // Check if we're running inside REAPER's web interface
    const checkReaperConnection = () => {
      if (window.ReaperWRB) {
        setIsConnected(true)
        // We could initialize communication here
        fetchTracks()
      } else {
        setIsConnected(false)
        console.log("Not running inside REAPER. ReaperWRB API not available.")
      }
    }

    checkReaperConnection()
    // Set up a timer to periodically check connection
    const interval = setInterval(checkReaperConnection, 5000)

    return () => clearInterval(interval)
  }, [])

  const fetchTracks = () => {
    // This is a placeholder function that would use ReaperWRB API
    // to fetch track information
    if (window.ReaperWRB) {
      // Example of how you might fetch data from REAPER
      // The actual implementation depends on the ReaperWRB API
      try {
        // This is just an example - actual command would depend on the API
        const result = window.ReaperWRB.getTrackList()
        if (result && Array.isArray(result)) {
          setTracks(result)
        }
      } catch (error) {
        console.error("Error fetching tracks:", error)
      }
    }
  }

  const handleButtonClick = () => {
    // Example of sending a command to REAPER
    if (window.ReaperWRB) {
      try {
        // This is a placeholder - actual commands would depend on the API
        window.ReaperWRB.runCommand("_SWS_SAVEALLSELWITHTIME")
        console.log("Command sent to REAPER")
      } catch (error) {
        console.error("Error sending command to REAPER:", error)
      }
    }
  }

  return (
    <div className="reaper-interface">
      <h2>{title}</h2>

      {isConnected ? (
        <div className="connection-status connected">Connected to REAPER</div>
      ) : (
        <div className="connection-status disconnected">
          Not connected to REAPER
        </div>
      )}

      <button onClick={handleButtonClick} disabled={!isConnected}>
        Send Command to REAPER
      </button>

      <div className="tracks-list">
        <h3>Tracks</h3>
        {tracks.length > 0 ? (
          <ul>
            {tracks.map((track, index) => (
              <li key={index}>{track}</li>
            ))}
          </ul>
        ) : (
          <p>No tracks available or not connected to REAPER</p>
        )}
      </div>
    </div>
  )
}

export default ReaperInterface
