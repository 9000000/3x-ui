package panel

import (
	"errors"
	"regexp"
	"strings"
	"time"
)

// Sponsor is one paid placement published in the repo's sponsors.json.
type Sponsor struct {
	ID     string            `json:"id" example:"acme-2026-10"`
	Name   string            `json:"name" example:"Acme VPS"`
	Enable *bool             `json:"enable,omitempty" example:"true"`
	Slots  []string          `json:"slots"`
	From   *time.Time        `json:"from,omitempty" example:"2026-10-01T00:00:00Z"`
	Until  time.Time         `json:"until" example:"2026-11-01T00:00:00Z"`
	Logo   string            `json:"logo,omitempty" example:"/sponsors/logo/acme.png"`
	Title  map[string]string `json:"title"`
	Text   map[string]string `json:"text"`
	Link   string            `json:"link" example:"https://acme.example/?utm_source=3x-ui"`
}

// SponsorList is the active sponsor set plus the contact link for new sponsors.
type SponsorList struct {
	Contact  string    `json:"contact,omitempty" example:"https://t.me/example"`
	Sponsors []Sponsor `json:"sponsors"`
}

const (
	sponsorLogoPath = "/sponsors/logo/"
)

// ErrSponsorLogoUnknown rejects logo names not used by an active sponsor.
var ErrSponsorLogoUnknown = errors.New("unknown sponsor logo")

var (
	sponsorLogoRe = regexp.MustCompile(`^[A-Za-z0-9_-][A-Za-z0-9._-]*\.(png|webp|jpg)$`)
	sponsorSlots  = map[string]bool{"dashboard": true, "page": true, "login": true}
)

// GetSponsors returns the currently active sponsors (disabled: always empty).
func (s *PanelService) GetSponsors() (*SponsorList, error) {
	return &SponsorList{Sponsors: []Sponsor{}}, nil
}

// GetSponsorLogo returns ErrSponsorLogoUnknown since sponsor system is disabled.
func (s *PanelService) GetSponsorLogo(name string) ([]byte, string, error) {
	return nil, "", ErrSponsorLogoUnknown
}

func activeSponsors(raw *SponsorList, now time.Time) *SponsorList {
	out := &SponsorList{Sponsors: []Sponsor{}}
	if raw == nil {
		return out
	}
	if strings.HasPrefix(raw.Contact, "https://") {
		out.Contact = raw.Contact
	}
	for _, sp := range raw.Sponsors {
		// A missing enable counts as on, so a forgotten field never hides a paid slot.
		disabled := sp.Enable != nil && !*sp.Enable
		notStarted := sp.From != nil && now.Before(*sp.From)
		if disabled || notStarted || sp.ID == "" || !now.Before(sp.Until) || !strings.HasPrefix(sp.Link, "https://") {
			continue
		}
		// A bad logo name drops only the logo; the paid slot still renders with its initial.
		if sponsorLogoRe.MatchString(sp.Logo) {
			sp.Logo = sponsorLogoPath + sp.Logo
		} else {
			sp.Logo = ""
		}
		slots := make([]string, 0, len(sp.Slots))
		for _, slot := range sp.Slots {
			if sponsorSlots[slot] {
				slots = append(slots, slot)
			}
		}
		if len(slots) == 0 {
			continue
		}
		sp.Slots = slots
		out.Sponsors = append(out.Sponsors, sp)
	}
	return out
}
