package Bot::Backbone::Service::Ticket::Tracker::FogBugz;
use Moose;

with qw( Bot::Backbone::Service::Ticket::Tracker );

use DOM::Tiny;
use WebService::FogBugz;

# ABSTRACT: ticket tracker lookups for FogBugz

=head1 SYNOPSIS

    service fogbugz_tickets => (
        service  => 'Ticket',
        trackers => [{
            type       => 'FogBugz',

            # use an external configuration
            config     => 'fbrc',

            # mandatory without config to specify the base URL
            base_url   => 'http://company.fogbugz.com/api.asp',

            # use token auth without config
            token      => 'secrettoken',

            # or use username/password auth without config
            email      => 'botuser@example.com',
            password   => 'secret',

            # And formatting and matching config...
            title      => 'Case %{issue}s: %{summary}s',
            link       => 'https://company.fogbugz.com/f/cases/%{issue}s',

            # Add attachments for Service::SlackChat messages
            attachments => [
                {
                    fallback   => 'Case %{issue}s: %{summary}s https://company.fogbugz.com/f/cases/%{issue}s',
                    color      => 'good',
                    title      => ':fogbugz: %{issue}s - %{title}s',
                    title_link => 'https://company.fogbugz.com/f/cases/%{issue}s',
                    title_icon => 'http://www.fogcreek.com/images/KiwiEnvelopeTransparent.png',
                    text       => '%{description}s',
                    mrkdwn_in  => ['text', 'fields'],
                    fields     => [
                        {
                            value => "*%{category}s*: %{project}s / %{area}s"
                                . "   *Status*:  %{status}s."
                                . "%{assigned_to}s",
                            short => 0,
                        },
                    ]
                }
            ],
            patterns   => [
                qr{(?<!/)\bbugzid:(?<issue>\d+)\b},
                qr{(?<![\[])\b(?<schema>https:)//company\.fogbugz\.com/f/cases/(?<issue>\d+)\b},
            ],
        }],
    );

=head1 DESCRIPTION

This works with L<Bot::Backbone::Service::Ticket> to perform FogBugz ticket lookups and summaries.

=head1 ATTRIBUTE

=head2 config

This will set the C<config> in L<WebService::FogBugz>.

=head2 base_url

This is the base URL of your FogBugz host instance. This is required when L</config> is not set.

=head2 token

This is required unless L</email> and L</password> are used. This is the authorization token to use when contacting the FogBugz web API.

=head2 email

This is required unless L</token> is used. This is the email to use for authentication.

=head2 password

This is required unless L</token> is used. This is the password to use for authentication.

=cut

has config   => ( is => 'ro' );
has base_url => ( is => 'ro' );
has token    => ( is => 'ro' );
has email    => ( is => 'ro' );
has password => ( is => 'ro' );

=head1 METHODS

=head2 lookup_issue

This is a very simple lookup that will grab the case metadata and return serveral fields.

=cut

sub lookup_issue {
    my ($self, $number) = @_;

    my $fb = WebService::FogBugz->new(
        config   => $self->config,
        base_url => $self->base_url,
        token    => $self->token,
        email    => $self->email,
        password => $self->password,
    );

    my $field_map = {
        sArea             => 'area',
        ixBug             => 'issue',
        sCategory         => 'category',
        sMilestone        => 'milestone',
        fOpen             => 'open',
        sPersonAssignedTo => 'assigned_to',
        sPriority         => 'priority',
        sProject          => 'project',
        sStatus           => 'status',
        sTitle            => 'title',
    };
    my $cols = join(",", keys(%$field_map));

    my $xml = $fb->request_method('search', {
        q    => $number,
        cols => $cols,
    });
    my $dom = DOM::Tiny->new($xml);
    return unless $dom;

    my $case = $dom->at("case[ixBug=$number]");
    return unless $case;

    my $issue = {issue => $number};

    my $kidz = $case->children();
    $kidz->each(
        sub {
            my ($e, $num) = @_;
            my $key = $field_map->{$e->tag} // $e->tag;
            $issue->{ $key } = $e->text;
        }
    );

    return $issue;
}

__PACKAGE__->meta->make_immutable;
