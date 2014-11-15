use strict;
use warnings;
package Dist::Zilla::Plugin::CheckSelfDependency;
# ABSTRACT: Check if your distribution declares a dependency on itself
# vim: set ts=8 sw=4 tw=78 et :

use Moose;
with 'Dist::Zilla::Role::AfterBuild',
    'Dist::Zilla::Role::FileFinderUser' => {
        default_finders => [ ':InstallModules' ],
    },
;
use Module::Metadata 1.000005;
use namespace::autoclean;

around dump_config => sub
{
    my ($orig, $self) = @_;
    my $config = $self->$orig;

    $config->{+__PACKAGE__} = {
        finder => $self->finder,
    };

    return $config;
};

sub after_build
{
    my $self = shift;

    my %prereqs = map { $_ => 1 }
        map { keys %$_ }
        map { values %$_ }
        grep { defined }
        @{ $self->zilla->prereqs->as_string_hash }{qw(configure build runtime test)};
    my %develop_prereqs = map { $_ => 1 }
        map { keys %$_ }
        map { values %$_ }
        grep { defined }
        $self->zilla->prereqs->as_string_hash->{develop};

    my $provides = $self->zilla->distmeta->{provides};  # copy, to avoid autovivifying

    my @errors;
    # when 'provides' data is mandatory, we will rely on what it says -
    # but for now, we will check our modules explicitly for provided packages.
    foreach my $file (@{$self->found_files})
    {
        $self->log_fatal(sprintf('Could not decode %s: %s', $file->name, $file->added_by))
            if $file->can('encoding') and $file->encoding eq 'bytes';

        my $fh;
        ($file->can('encoding')
            ? open $fh, sprintf('<:encoding(%s)', $file->encoding), \$file->encoded_content
            : open $fh, '<', \$file->content)
                or $self->log_fatal('cannot open handle to ' . $file->name . ' content: ' . $!);

        my @packages = Module::Metadata->new_from_handle($fh, $file->name)->packages_inside;
        foreach my $package (@packages)
        {
            if (exists $prereqs{$package}
                or (exists $develop_prereqs{$package}
                    and not exists $provides->{$package}))
            {
                push @errors, $package . ' is listed as a prereq, but is also provided by this dist ('
                    . $file->name . ')!'
            }
        }
    }

    $self->log_fatal(@errors) if @errors;
}

__PACKAGE__->meta->make_immutable;
__END__

=pod

=for Pod::Coverage after_build

=head1 SYNOPSIS

In your F<dist.ini>:

    [CheckSelfDependency]

=head1 DESCRIPTION

=for stopwords indexable

This is a L<Dist::Zilla> plugin that runs in the I<after build> phase, which
checks all of your module prerequisites (all phases, all types except develop) to confirm
that none of them refer to modules that are B<provided> by this distribution
(that is, the metadata declares the module is indexable).

In addition, all modules B<in> the distribution are checked against all module
prerequisites (all phases, all types B<including> develop). Thus, it is
possible to ship a L<Dist::Zilla> plugin and use (depend on) yourself, but
errors such as declaring a dependency on C<inc::HelperPlugin> are still caught.

While some prereq providers (e.g. L<C<[AutoPrereqs]>|Dist::Zilla::Plugin::AutoPrereqs>)
do not inject dependencies found internally, there are many plugins that
generate code and also inject the prerequisites needed by that code, without
regard to whether some of those modules might be provided by your dist.

If such modules are found, the build fails.  To remedy the situation, remove
the plugin that adds the prerequisite, or remove the prerequisite itself with
L<C<[RemovePrereqs]>|Dist::Zilla::Plugin::RemovePrereqs>. (Remember that
plugin order is significant -- you need to remove the prereq after it has been
added.)

=head1 CONFIGURATION OPTIONS

=head2 C<finder>

=for stopwords FileFinder

This is the name of a L<FileFinder|Dist::Zilla::Role::FileFinder> for finding
modules to check.  The default value is C<:InstallModules>; this option can be
used more than once.

Other predefined finders are listed in
L<Dist::Zilla::Role::FileFinderUser/default_finders>.
You can define your own with the
L<[FileFinder::ByName]|Dist::Zilla::Plugin::FileFinder::ByName> and
L<[FileFinder::Filter]|Dist::Zilla::Plugin::FileFinder::Filter> plugins.

=head1 SUPPORT

=for stopwords irc

Bugs may be submitted through L<the RT bug tracker|https://rt.cpan.org/Public/Dist/Display.html?Name=Dist-Zilla-Plugin-CheckSelfDependency>
(or L<bug-Dist-Zilla-Plugin-CheckSelfDependency@rt.cpan.org|mailto:bug-Dist-Zilla-Plugin-CheckSelfDependency@rt.cpan.org>).
I am also usually active on irc, as 'ether' at C<irc.perl.org>.

=cut
