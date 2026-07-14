package headless

import (
	"encoding/xml"
	"io"
	"strconv"
)

type testSuite struct {
	XMLName  xml.Name   `xml:"testsuite"`
	Name     string     `xml:"name,attr"`
	Tests    int        `xml:"tests,attr"`
	Failures int        `xml:"failures,attr"`
	Skipped  int        `xml:"skipped,attr"`
	Time     string     `xml:"time,attr"`
	Cases    []testCase `xml:"testcase"`
}

type testCase struct {
	Name      string       `xml:"name,attr"`
	ClassName string       `xml:"classname,attr"`
	Time      string       `xml:"time,attr"`
	Failure   *testFailure `xml:"failure,omitempty"`
	Skipped   *testSkipped `xml:"skipped,omitempty"`
}

type testFailure struct {
	Message string `xml:"message,attr"`
	Text    string `xml:",chardata"`
}

type testSkipped struct {
	Message string `xml:"message,attr,omitempty"`
}

// WriteJUnit serializes a headless report as a portable JUnit test suite.
func WriteJUnit(w io.Writer, report Report) error {
	suite := testSuite{Name: "os-init modules", Tests: len(report.Results)}
	seconds := report.FinishedAt.Sub(report.StartedAt).Seconds()
	if seconds < 0 {
		seconds = 0
	}
	suite.Time = strconv.FormatFloat(seconds, 'f', 3, 64)
	for _, result := range report.Results {
		item := testCase{
			Name:      result.ModuleID + "/" + string(result.Operation),
			ClassName: "os-init.module",
			Time:      strconv.FormatFloat(float64(result.DurationMS)/1000, 'f', 3, 64),
		}
		switch result.Status {
		case "failed":
			suite.Failures++
			item.Failure = &testFailure{Message: result.Error, Text: result.LogFile}
		case "skipped", "limited":
			suite.Skipped++
			item.Skipped = &testSkipped{Message: result.Error}
		}
		suite.Cases = append(suite.Cases, item)
	}
	if _, err := io.WriteString(w, xml.Header); err != nil {
		return err
	}
	encoder := xml.NewEncoder(w)
	encoder.Indent("", "  ")
	if err := encoder.Encode(suite); err != nil {
		return err
	}
	_, err := io.WriteString(w, "\n")
	return err
}
