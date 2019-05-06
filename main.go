package main

import (
    "os"
    "fmt"
	"net/http"
    "io/ioutil"
    "encoding/json"
)

var (
    APP_ID     = "NULL"
    SECRET_KEY = "NULL"
)

type DeezerTokenResponse struct {
    Token string `json:"access_token"`
    Expires int64 `json:"expires"`
}

func get_code (w http.ResponseWriter, r *http.Request) {
    code, ok := r.URL.Query()["code"]
    if !ok {
        fmt.Printf("Can't get auth code!")
        os.Exit(1)
    } else {
        res, err := http.Get("https://connect.deezer.com/oauth/access_token.php?app_id=" + string(APP_ID) + "&secret=" + string(SECRET_KEY) + "&code=" + string(code[0]) + "&output=json")
        if err != nil {
            fmt.Printf("Can't get token!")
            os.Exit(1)
        }
	//defer res.Body.Close()
        body, err := ioutil.ReadAll(res.Body)
        var json_body = new(DeezerTokenResponse)
        json.Unmarshal([]byte(body), &json_body)
        fmt.Printf(json_body.Token)
        fmt.Fprint(w, "Token saved successfully! You can close this tab")
        os.Exit(0)
    }
}

func main () {
    http.HandleFunc("/", get_code)
	http.ListenAndServe(":80", nil)
}

